//
//  GPUVFrameSourceVideo.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVFrameSourceVideo.h"

#import <QuartzCore/QuartzCore.h>

#import "BGRAToBT709Converter.h"

static void* const AVLoopPlayerQueuePlayerStatusObservationContext =
  (void*)&AVLoopPlayerQueuePlayerStatusObservationContext;
static void* const AVLoopPlayerCurrentItemObservationContext =
  (void*)&AVLoopPlayerCurrentItemObservationContext;
static void* const AVLoopPlayerCurrentItemStatusObservationContext =
  (void*)&AVLoopPlayerCurrentItemStatusObservationContext;

#define LOG_DISPLAY_LINK_TIMINGS
#define STORE_TIMES

// Private API

@interface GPUVFrameSourceVideo ()

// Player instance objects to decode CoreVideo buffers from an asset item

@property (nonatomic, retain) AVQueuePlayer *player;

@property (nonatomic, retain) AVPlayerItemVideoOutput *playerItemVideoOutput;
// The player item associated with the playerItemVideoOutput
@property (nonatomic, retain) AVPlayerItem *videoOutputPlayerItem;

@property (nonatomic, retain) dispatch_queue_t playerQueue;

@property (nonatomic, assign) int frameNum;

// The integer count of the number of times the video has looped.
// This value starts out as zero, it then increases each time
// the active item changes.

@property (nonatomic, assign) int loopCount;

// If a reported time is larger than this time, then on the final frame

@property (nonatomic, assign) CFTimeInterval finalFrameTime;

#if defined(STORE_TIMES)
@property (nonatomic, retain) NSMutableArray *times;
#endif // STORE_TIMES

@end

@implementation GPUVFrameSourceVideo
{
    id _notificationToken;
    BOOL _addedObservers;
}

- (void) dealloc
{
  [self.playerItemVideoOutput setDelegate:nil queue:nil];
  self.playerQueue = nil;
  return;
}

- (NSString*) description
{
  int width = self.width;
  int height = self.height;
  
  return [NSString stringWithFormat:@"GPUVFrameSourceVideo %p (%@) %dx%d ",
          self,
          self.uid,
          width,
          height];
}

// Map host time to item time for the current item.

- (CMTime) itemTimeForHostTime:(CFTimeInterval)hostTime
{
  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
  CMTime currentItemTime = [playerItemVideoOutput itemTimeForHostTime:hostTime];
  return currentItemTime;
}

// Given a host time offset, return a GPUVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.
// The hostPresentationTime indicates the host time when the
// decoded frame would be displayed.
// The presentationTimePtr pointer provides a way to query the
// DTS (display time stamp) of the decoded frame in the H.264 stream.
// Note that presentationTimePtr can be NULL.

- (GPUVFrame*) frameForHostTime:(CFTimeInterval)hostTime
           hostPresentationTime:(CFTimeInterval)hostPresentationTime
            presentationTimePtr:(float*)presentationTimePtr
{
  if (self.videoOutputPlayerItem == nil) {
    NSLog(@"player not ready yet in frameForHostTime");
    return nil;
  }
  
  self.syncTime = hostPresentationTime;
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  if ((1)) {
    NSLog(@"%@ : frameForHostTime at host time %.3f : CACurrentMediaTime() %.3f", self, hostTime, CACurrentMediaTime());
  }
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  // FIXME: Seems that a lot of CPU time in itemTimeForHostTime is being
  // spent getting the master clock for the host. It is better performance
  // wise to always set the master clock at the start of playback ?
  
  CMTime currentItemTime = [self itemTimeForHostTime:hostTime];
  
  // FIXME: would it be possible to use the RGB stream as the master timeline
  // and then treat the alpha timeline as the slave timeline so that this
  // itemTimeForHostTime to convert hostTime -> currentItemTime would only
  // be done for one of the timelines? Could this avoid the sync issue related
  // to calling seek and setRate at very slightly different times? Would the
  // next hasNewPixelBufferForItemTime always be in sync for the 2 streams?
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  NSLog(@"host time %0.3f -> item time %0.3f", hostTime, CMTimeGetSeconds(currentItemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  return [self frameForItemTime:currentItemTime
                       hostTime:hostTime
           hostPresentationTime:hostPresentationTime
            presentationTimePtr:presentationTimePtr];
}

// Get frame that corresponds to item time. The item time range is
// (0.0, (N * frameDuration))
// Note that hostTime is used only for debug output here

- (GPUVFrame*) frameForItemTime:(CMTime)itemTime
                       hostTime:(CFTimeInterval)hostTime
           hostPresentationTime:(CFTimeInterval)hostPresentationTime
            presentationTimePtr:(float*)presentationTimePtr
{
  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
  
  GPUVFrame *nextFrame = nil;
  
  // Map time offset to item time
  
#if defined(STORE_TIMES)
  if (self.times == nil) {
    self.times = [NSMutableArray array];
  }
  
  NSMutableArray *timeArr = [NSMutableArray array];
#endif // STORE_TIMES
  
  // FIXME: Seems that a lot of CPU time in itemTimeForHostTime is being
  // spent getting the master clock for the host. It is better performance
  // wise to always set the master clock at the start of playback ?
  
  // FIXME: would it be possible to use the RGB stream as the master timeline
  // and then treat the alpha timeline as the slave timeline so that this
  // itemTimeForHostTime to convert hostTime -> currentItemTime would only
  // be done for one of the timelines? Could this avoid the sync issue related
  // to calling seek and setRate at very slightly different times? Would the
  // next hasNewPixelBufferForItemTime always be in sync for the 2 streams?
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  NSLog(@"host time %0.3f -> item time %0.3f", hostTime, CMTimeGetSeconds(itemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
  
#if defined(STORE_TIMES)
  // Media time when this frame data is being processed, ahead of hostTime since
  // the hostTime value is determined in relation to vsync bounds.
  [timeArr addObject:@(CACurrentMediaTime())];
  [timeArr addObject:@(hostTime)];
  [timeArr addObject:@(CMTimeGetSeconds(itemTime))];
#endif // STORE_TIMES

  float presentationTimeSeconds = -1;
  
  if ([playerItemVideoOutput hasNewPixelBufferForItemTime:itemTime]) {
    // Grab the pixel bufer for the current time
    
    CMTime presentationTime = kCMTimeZero;
    
    CVPixelBufferRef rgbPixelBuffer = [playerItemVideoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:&presentationTime];

    presentationTimeSeconds = CMTimeGetSeconds(presentationTime);
    
    if (rgbPixelBuffer != NULL) {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
      NSLog(@"LOADED %5@  frame for item time %0.3f", self.uid, CMTimeGetSeconds(itemTime));
      NSLog(@"                     display time %0.3f", presentationTimeSeconds);
#endif // LOG_DISPLAY_LINK_TIMINGS
      
      nextFrame = [[GPUVFrame alloc] init];
      nextFrame.yCbCrPixelBuffer = rgbPixelBuffer;
      nextFrame.frameNum = [GPUVFrame calcFrameNum:presentationTimeSeconds fps:self.FPS];
      CVPixelBufferRelease(rgbPixelBuffer);
      
#if defined(STORE_TIMES)
      [timeArr addObject:@(presentationTimeSeconds)];
      [timeArr addObject:@(nextFrame.frameNum)];
#endif // STORE_TIMES
    } else {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
      NSLog(@"did not load RGB frame for item time %0.3f", CMTimeGetSeconds(itemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
      
#if defined(STORE_TIMES)
      [timeArr addObject:@(-1)];
      [timeArr addObject:@(-1)];
#endif // STORE_TIMES
    }
  } else {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
    NSLog(@"hasNewPixelBufferForItemTime is FALSE at vsync time %0.3f", CMTimeGetSeconds(itemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
    
#if defined(STORE_TIMES)
    [timeArr addObject:@(-1)];
    [timeArr addObject:@(-1)];
#endif // STORE_TIMES
  }
  
#if defined(STORE_TIMES)
  [self.times addObject:timeArr];
#endif // STORE_TIMES
  
  // The logic above attempts to load a specific video frame, but it is possible
  // that the clock time is now at or past the final frame of video. Check for
  // this "final frame" condition even is loading a video frame was not
  // successful to handle the case where a frame at the end of the video
  // has a display duration longer than one frame.
  
  if (self.finalFrameBlock != nil) {
    float itemSeconds = CMTimeGetSeconds(itemTime);
    
    //NSLog(@"itemSeconds >= finalFrameTime : %.3f >= %.3f", itemSeconds, self.finalFrameTime);
    
    if (itemSeconds >= self.finalFrameTime) {
      NSLog(@"past finalFrameTime %.3f >= %.3f", itemSeconds, self.finalFrameTime);
      
      self.finalFrameBlock();
    }
  }
  
  if (presentationTimePtr) {
    *presentationTimePtr = presentationTimeSeconds;
  }
  
  return nextFrame;
}

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been decoded.

- (BOOL) hasMoreFrames;
{
  return TRUE;
}

// Init from asset name

- (BOOL) loadFromAsset:(NSString*)resFilename
{
  NSString *path = [[NSBundle mainBundle] pathForResource:resFilename ofType:nil];
  NSAssert(path, @"path is nil");
  
  NSURL *assetURL = [NSURL fileURLWithPath:path];
  
  return [self decodeFromRGBResourceVideo:assetURL];
}

// Init from asset or remote URL

- (BOOL) loadFromURL:(NSURL*)URL
{
  return [self decodeFromRGBResourceVideo:URL];
}

// Init video frame from the indicated URL

- (BOOL) decodeFromRGBResourceVideo:(NSURL*)URL
{
  NSArray<AVPlayerItem *> *queueItems = @[
                                          [AVPlayerItem playerItemWithURL:URL],
                                          [AVPlayerItem playerItemWithURL:URL]
                                          ];
  
  AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:queueItems];
  
  self.player = player;
  
  NSLog(@"PlayerItem URL %@", URL);
  
  __weak typeof(self) weakSelf = self;
  
  // Default setting for end of clip will stop playback
  
  self.playedToEndBlock = ^{
    NSLog(@"GPUVFrameSourceVideo.playedToEndBlock %.3f", CACurrentMediaTime());
    [weakSelf stop];
  };
  
  // Async logic to parse M4V headers to get tracks and other metadata

  AVAsset *asset = [self.player.currentItem asset];

  NSAssert(asset, @"curent item asset is nil");
  
  NSArray *assetKeys = @[@"duration", @"playable", @"tracks"];
  
  [asset loadValuesAsynchronouslyForKeys:assetKeys completionHandler:^{
    
    // FIXME: Save @"duration" when available here
    
    // Check "playable"
    
//    if ([asset statusOfValueForKey:@"playable" error:nil] == AVKeyValueStatusLoaded) {
//      if ([asset isPlayable] == FALSE) {
//        NSLog(@"asset is NOT playable");
//        assert(0);
//      }
//    }
    
    if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        BOOL worked = [weakSelf asyncTracksReady:asset];

        if (worked == FALSE) {
          // In the failed to load case, invoke callback
          if (weakSelf.loadedBlock != nil) {
            weakSelf.loadedBlock(FALSE);
            weakSelf.loadedBlock = nil;
          }
        }
      });
    }
    
  }];
  
  return TRUE;
}

// Util method that creates AVPlayerItemVideoOutput instance

- (void) makeVideoOutput {
#if defined(DEBUG)
  NSAssert(self.playerItemVideoOutput == nil, @"self.playerItemVideoOutput must be nil");
#endif // DEBUG
  
  NSDictionary *pixelBufferAttributes = [BGRAToBT709Converter getPixelBufferAttributes];
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionaryWithDictionary:pixelBufferAttributes];
  
  // Add kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
  
  mDict[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  
  pixelBufferAttributes = [NSDictionary dictionaryWithDictionary:mDict];
  
  // FIXME: Create AVPlayerItemVideoOutput after AVPlayerItem status is ready to play
  // https://forums.developer.apple.com/thread/27589
  // https://github.com/seriouscyrus/AVPlayerTest
  
  self.playerItemVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];;
  
  // FIXME: does this help ?
  self.playerItemVideoOutput.suppressesPlayerRendering = TRUE;
  
  self.playerQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
  
  __weak typeof(self) weakSelf = self;
  
  [self.playerItemVideoOutput setDelegate:weakSelf queue:self.playerQueue];
  
#if defined(DEBUG)
  assert(self.playerItemVideoOutput.delegateQueue == self.playerQueue);
#endif // DEBUG
}

// Async callback that is invoked when the "tracks" property has been
// loaded and is ready to be inspected.

- (BOOL) asyncTracksReady:(AVAsset*)asset
{
  NSLog(@"asyncTracksReady");
  
  // Verify that the status for this specific key is ready to be read
  
#if defined(DEBUG)
  // Callback must be processed on main thread
  
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  
  AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:nil];
  NSAssert(status == AVKeyValueStatusLoaded, @"status != AVKeyValueStatusLoaded : %d", (int)status);
#endif // DEBUG
  
  NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
  int numTracks = (int) [videoTracks count];
  
  if (numTracks == 0) {
    return FALSE;
  }
  
  // Choose the first video track. Ignore other tracks if found
  const int videoTrackOffset = 0;
  AVAssetTrack *videoTrack = [videoTracks objectAtIndex:videoTrackOffset];
  
  // Must be self contained
  
  if (videoTrack.isSelfContained != TRUE) {
    if ([self isKindOfClass:AVURLAsset.class]) {
      AVURLAsset *urlAsset = (AVURLAsset*) asset;
      NSString *path = [urlAsset.URL path];
      NSLog(@"videoTrack.isSelfContained must be TRUE for \"%@\"", path);
    }
    return FALSE;
  }
  
  CGSize itemSize = videoTrack.naturalSize;
  NSLog(@"video track naturalSize w x h : %d x %d", (int)itemSize.width, (int)itemSize.height);
  
  // Allocate render buffer once asset dimensions are known
  
  // Writing to this property must be done on main thread
  //strongSelf.resizeTextureSize = itemSize;
  self.width = (int) itemSize.width;
  self.height = (int) itemSize.height;
  
  //[weakSelf makeInternalMetalTexture];
  
  CMTimeRange timeRange = videoTrack.timeRange;
  float trackDuration = (float)CMTimeGetSeconds(timeRange.duration);
  NSLog(@"video track time duration %0.3f", trackDuration);
  
  CMTime frameDurationTime = videoTrack.minFrameDuration;
  float frameDurationSeconds = (float)CMTimeGetSeconds(frameDurationTime);
  NSLog(@"video track frame duration %0.3f", frameDurationSeconds);
  
  // Once display frame interval has been parsed, create display
  // frame timer but be sure it is created on the main thread
  // and that this method invocation completes before the
  // next call to dispatch_async() to start playback.
  
  {
    // Note that writing to FPS members must be executed on the
    // main thread.
    
    float FPS = 1.0f / frameDurationSeconds;
    if (FPS <= 30.001 && FPS >= 29.999) {
      FPS = 30;
      frameDurationSeconds = 1.0f / 30.0f;
    }
    self.FPS = FPS;
    self.frameDuration = frameDurationSeconds;
    
    //[self makeDisplayLink];
  }
  
  {
    // Calculate the frame number of the final frame

    self.finalFrameTime = trackDuration - frameDurationSeconds - (frameDurationSeconds * 0.10);
    
    NSLog(@"video finalFrameTime %.3f", self.finalFrameTime);
  }

  // Init player with current item, seek to time = 0.0
  // but do not start playback automatically
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
  NSLog(@"video track nominal frame duration %0.3f", nominalFrameRate);
  
  [self startObservingPlayerAndItem];
  
  return TRUE;
}

- (void) assetReadyToPlay
{
  if (self.playerItemVideoOutput == nil) {
    // First invocation
    
    [self makeVideoOutput];
    
    [self.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
  }
  
  AVPlayerItem *playerItem = self.player.currentItem;

  // In some cases, this method can be invoked when only a
  // single item is in the queue, since the one that was just
  // display has not been appened to the back of the item
  // queue again.
  
  if (self.videoOutputPlayerItem == nil) {
    // Init case, add output and set
    [playerItem addOutput:self.playerItemVideoOutput];
    self.videoOutputPlayerItem = playerItem;
    self.loopCount = 0;
    
    NSLog(@"OUTPUT init %p", playerItem);
  } else if (self.videoOutputPlayerItem == playerItem) {
    // Activate the item that is currently active
    //[playerItem removeOutput:self.playerItemVideoOutput];
    //[playerItem addOutput:self.playerItemVideoOutput];
    
    //NSLog(@"OUTPUT remove/add %p -> %p", playerItem, playerItem);
    
    NSLog(@"OUTPUT NOP same item %p", playerItem);
  } else {
    // Changing the item connected to the video output
#if defined(DEBUG)
    NSAssert(playerItem != self.videoOutputPlayerItem, @"playerItem != self.videoOutputPlayerItem");
#endif // DEBUG
    [self.videoOutputPlayerItem removeOutput:self.playerItemVideoOutput];
    if (1) {
      // FIXME: Destroy the old output and create a new one ??
    }
    [playerItem addOutput:self.playerItemVideoOutput];
    NSLog(@"OUTPUT changed remove/add %p -> %p", self.videoOutputPlayerItem, playerItem);
    self.videoOutputPlayerItem = playerItem;
    
    // Resync current item time to next frame sync time
    
    //[self seekToTimeZero];
    //[self setRate:self.playRate atHostTime:self.syncTime];
    //NSLog(@"Player setRate with current time %.3f", CMTimeGetSeconds(self.player.currentTime));
    
    [self syncStart:self.playRate itemTime:0.0 atHostTime:self.syncTime];
    
    //NSLog(@"incr loopCount from %d to %d", self.loopCount, self.loopCount+1);
    self.loopCount = self.loopCount + 1;
  }
}

// Kick of play operation

- (void) play
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  if (self.playRate == 0.0f) {
    self.playRate = 1.0f;
  }

  if ((0)) {
    [self.player play];
  } else {
    CFTimeInterval syncTime = CACurrentMediaTime();
    [self play:syncTime];
  }
}

- (void) stop
{
  [self stopObservingPlayerAndItem];
  
  [self.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
  
  self.playerItemVideoOutput = nil;
  
  [self.player setRate:0.0];
}

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  self.playRate = rate;
  
  // Sync item time 0.0 to supplied host time (system clock)
  
  AVPlayer *player = self.player;
  
  NSLog(@"AVPlayer playWithPreroll : %.2f", rate);
  
  self.loopCount = 0;
  
  player.automaticallyWaitsToMinimizeStalling = FALSE;
  
  [player prerollAtRate:rate completionHandler:^(BOOL finished){
    // FIXME: Should finished be passed to block to cancel?
    // FIXME: Should pass rate to block
    
    if (finished) {
      block();
    }
  }];
}

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
        itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime
{
  CMTime syncTimeCM = CMTimeMake(itemTime * 1000.0f, 1000);
  [self.player seekToTime:syncTimeCM completionHandler:^(BOOL finished){
    if (finished) {
    CMTime hostTimeCM = CMTimeMake(atHostTime * 1000.0f, 1000);
    [self.player setRate:rate time:kCMTimeInvalid atHostTime:hostTimeCM];
    }
  }];
}

// Invoke player setRate to actually begin playing back a video
// source once playWithPreroll invokes the block callback
// with a specific host time to sync to. Note that this API
// always uses the current time as the sync point.

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime
{
  CMTime hostTimeCM = CMTimeMake(atHostTime * 1000.0f, 1000);
  [self.player setRate:rate time:kCMTimeInvalid atHostTime:hostTimeCM];
}

// Kick of play operation where the zero time implicitly
// gets synced to the indicated host time. This means
// that 2 different calls to play on two different
// players will start in sync.

- (void) play:(CFTimeInterval)syncTime
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  // Sync item time 0.0 to supplied host time (system clock)
  
  AVPlayerItem *item = self.player.currentItem;
  
  NSLog(@"AVPlayer play sync itemTime 0.0 to %.3f", syncTime);
  
  self.player.automaticallyWaitsToMinimizeStalling = FALSE;
  CMTime hostTimeCM = CMTimeMake(syncTime * 1000.0f, 1000);
  //[self.player setRate:1.0 time:kCMTimeZero atHostTime:hostTimeCM];
  [self.player setRate:1.0 time:kCMTimeInvalid atHostTime:hostTimeCM];
  
  NSLog(@"play AVPlayer.item %d / %d : %0.3f", (int)item.currentTime.value, (int)item.currentTime.timescale, CMTimeGetSeconds(item.currentTime));
}

// restart will rewind and then play, in the case where the video is already
// playing then a call to restart will just rewind.

- (void) restart {
//  [self seekToTimeZero];
//
//  AVPlayerTimeControlStatus timeControlStatus = self.player.timeControlStatus;
//
//  if (timeControlStatus == AVPlayerTimeControlStatusPlaying ||
//      timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
//    // Currently playing
//  } else {
//    // Not playing
//    [self play];
//  }
  
//  self.loopCount += 1;
//  
//  if (self.loopCount >= 5) {
//    ;
//  }
  
  // Advance to next item
  
  AVPlayerItem *currentItemBefore = self.player.currentItem;
  
  [self.player advanceToNextItem];
  
  AVPlayerItem *currentItemAfter = self.player.currentItem;
  
  NSAssert(currentItemBefore != currentItemAfter, @"did not switch");
  
  // Swap output
  
  [self assetReadyToPlay];
  
//  CFTimeInterval syncTime = self.syncTime;
//  float playRate = self.playRate;
//
//  [self seekToTimeZero];
//  [self setRate:playRate atHostTime:syncTime];
}

#pragma mark - AVPlayerItemOutputPullDelegate

// FIXME: Need to mark state to indicate that media has been
// parsed and is now ready to play. But, cannot directly
// operate on a displayLink here since there is not a 1 to 1
// mapping between a display link and an output. A callback
// into the view or some other type of notification will
// be needed to signal that the media is ready to play.

- (void)outputMediaDataWillChange:(AVPlayerItemOutput*)sender
{
  NSLog(@"outputMediaDataWillChange : sender %p", sender);
  
  __weak typeof(self) weakSelf = self;
  
  dispatch_async(dispatch_get_main_queue(), ^{
    if (weakSelf.loadedBlock != nil) {
      weakSelf.loadedBlock(TRUE);
      weakSelf.loadedBlock = nil;
    }
  });
  
  return;
}

- (void)startObservingPlayerAndItem
{
  if (_addedObservers == NO)
  {
    AVQueuePlayer *player = self.player;
    [player addObserver:self forKeyPath:@"status"
                options:NSKeyValueObservingOptionNew context:AVLoopPlayerQueuePlayerStatusObservationContext];
    [player addObserver:self forKeyPath:@"currentItem"
                options:NSKeyValueObservingOptionOld context:AVLoopPlayerCurrentItemObservationContext];
    [player addObserver:self forKeyPath:@"currentItem.status"
                options:NSKeyValueObservingOptionNew context:AVLoopPlayerCurrentItemStatusObservationContext];
    _addedObservers = YES;
  }
}

- (void)stopObservingPlayerAndItem
{
  if (_addedObservers)
  {
    AVQueuePlayer *player = self.player;
    [player removeObserver:self forKeyPath:@"status" context:AVLoopPlayerQueuePlayerStatusObservationContext];
    [player removeObserver:self forKeyPath:@"currentItem" context:AVLoopPlayerCurrentItemObservationContext];
    [player removeObserver:self forKeyPath:@"currentItem.status" context:AVLoopPlayerCurrentItemStatusObservationContext];
    _addedObservers = NO;
  }
}

- (void)outputSequenceWasFlushed:(AVPlayerItemOutput*)output
{
  NSLog(@"%p outputSequenceWasFlushed : current AVPlayerItem %p", self, self.videoOutputPlayerItem);
  
  return;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)changeDictionary context:(void *)context
{
  const BOOL logAllObserved = TRUE;
  
  if (logAllObserved) {
  NSLog(@"observeValueForKeyPath \"%@\" : %@", keyPath, changeDictionary);
  NSLog(@"self.player.items count %d", (int)self.player.items.count);
  }
  
  if (context == AVLoopPlayerQueuePlayerStatusObservationContext)
  {
    AVPlayerStatus newPlayerStatus = (AVPlayerStatus)[[changeDictionary objectForKey:NSKeyValueChangeNewKey] unsignedIntegerValue];
    if (newPlayerStatus == AVPlayerStatusFailed) {
      AVQueuePlayer *player = (AVQueuePlayer *)object;
      NSLog(@"End looping since player has failed with error %@", player.error);
      [self stop];
    }
  }
  else if (context == AVLoopPlayerCurrentItemObservationContext)
  {
    AVQueuePlayer *player = (AVQueuePlayer *)object;
    
    if ([[player items] count] == 0)
    {
      NSLog(@"Play queue emptied out due to bad player item. End looping.");
      [self stop];
    }
    else
    {
      // Append the previous current item to the player's queue.
      AVPlayerItem *itemRemoved = changeDictionary[NSKeyValueChangeOldKey];
      
      /*
       An initial change from a nil currentItem yields NSNull here. Check
       to make sure the class is AVPlayerItem before appending it to the
       end of the queue.
       */
      if ([itemRemoved isKindOfClass:[AVPlayerItem class]])
      {
        [self stopObservingPlayerAndItem];
        [player insertItem:itemRemoved afterItem:nil];
        [self startObservingPlayerAndItem];
        
        if (logAllObserved) {
        NSLog(@"remove and append AVPlayerItem %@", itemRemoved);
        NSLog(@"player.items %@", player.items);
        }
      }
    }
  }
  else if (context == AVLoopPlayerCurrentItemStatusObservationContext)
  {
    AVPlayerItemStatus newItemStatus = (AVPlayerItemStatus)[[changeDictionary objectForKey:NSKeyValueChangeNewKey] unsignedIntegerValue];
    if (newItemStatus == AVPlayerItemStatusFailed) {
      AVQueuePlayer *player = (AVQueuePlayer *)object;
      NSLog(@"End looping since player item has failed with error %@", player.currentItem.error);
      [self stop];
    } else if (newItemStatus == AVPlayerItemStatusReadyToPlay) {
      
      if (logAllObserved) {
        NSLog(@"AVPlayerItemStatusReadyToPlay : AVPlayerItem %p : host time %.3f", self.player.currentItem, CACurrentMediaTime());
        NSLog(@"AVPlayerStatusReadyToPlay: Asset current time %.3f", CMTimeGetSeconds(self.player.currentItem.currentTime));
        NSLog(@"player.items %@", self.player.items);
      }

      NSAssert(self.player.status == AVPlayerStatusReadyToPlay, @"player.status != AVPlayerStatusReadyToPlay : %d", (int)self.player.status);
      
      // Invoke assetReadyToPlay only in the init case, for the very first item that becomes ready
      
      if (self.videoOutputPlayerItem == nil) {
        [self assetReadyToPlay];
      }
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:changeDictionary context:context];
  }
}

// Define a CMTimescale that will be used by the player, this
// implicitly assumes that the timeline has a rate of 0.0
// and that the caller will start playback by setting the
// timescale rate.

- (void) useMasterClock:(CMClockRef)masterClock
{
  self.player.masterClock = masterClock;
}

- (void) seekToTimeZero
{
  [self.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished){
    // nop
  }];
}

@end
