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

#import "GPUVPlayerVideoOutput.h"

#define LOG_DISPLAY_LINK_TIMINGS
#define STORE_TIMES

// Private API

@interface GPUVFrameSourceVideo ()

@property (nonatomic, retain) NSMutableArray<AVPlayerItem *> *queueItems;

@property (nonatomic, assign) BOOL isPlayer2Active;
@property (nonatomic, retain) GPUVPlayerVideoOutput *playerVideoOutput1;
@property (nonatomic, retain) GPUVPlayerVideoOutput *playerVideoOutput2;

@property (nonatomic, assign) int frameNum;

#if defined(STORE_TIMES)
@property (nonatomic, retain) NSMutableArray *times;
#endif // STORE_TIMES

@end

@implementation GPUVFrameSourceVideo
{
}

- (nullable instancetype) init
{
  if (self = [super init]) {
    self.playerVideoOutput1 = [[GPUVPlayerVideoOutput alloc] init];
    self.playerVideoOutput2 = [[GPUVPlayerVideoOutput alloc] init];
  }
  
  return self;
}

- (void) dealloc
{
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

- (GPUVPlayerVideoOutput*) getCurrentPlayerVideoOutput
{
  if (self.isPlayer2Active) {
    NSLog(@"playerVideoOutput2 is active");
    return self.playerVideoOutput2;
  } else {
    NSLog(@"playerVideoOutput1 is active");
    return self.playerVideoOutput1;
  }
}

- (GPUVPlayerVideoOutput*) getNextPlayerVideoOutput
{
  if (self.isPlayer2Active) {
    return self.playerVideoOutput1;
  } else {
    return self.playerVideoOutput2;
  }
}

// Map host time to item time for the current item.

- (CMTime) itemTimeForHostTime:(CFTimeInterval)hostTime
{
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  AVPlayerItemVideoOutput *playerItemVideoOutput = pvo.playerItemVideoOutput;
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
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  
  if (pvo.isPlaying == FALSE) {
    NSLog(@"player not playing yet in frameForHostTime");
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
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  AVPlayerItemVideoOutput *playerItemVideoOutput = pvo.playerItemVideoOutput;
  
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
    
    //NSLog(@"itemSeconds >= finalFrameTime : %.3f >= %.3f", itemSeconds, pvo.finalFrameTime);
    
    if (itemSeconds >= pvo.finalFrameTime) {
      NSLog(@"past finalFrameTime %.3f >= %.3f", itemSeconds, pvo.finalFrameTime);
      
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

- (void) setLoadedBlockCallbacks
{
  __weak typeof(self) weakSelf = self;
  
  self.playerVideoOutput1.loadedBlock = ^(BOOL success){
    [weakSelf loadedCallback:success];
  };
  
  self.playerVideoOutput2.loadedBlock = ^(BOOL success){
    [weakSelf loadedCallback:success];
  };
}

// Init video frame from the indicated URL

- (BOOL) decodeFromRGBResourceVideo:(NSURL*)URL
{
  NSArray<AVPlayerItem *> *queueItems = @[
                                          [AVPlayerItem playerItemWithURL:URL],
                                          [AVPlayerItem playerItemWithURL:URL]
                                          ];
  
  self.queueItems = [NSMutableArray arrayWithArray:queueItems];
  
  NSLog(@"PlayerItem URL %@", URL);
  
  __weak typeof(self) weakSelf = self;
  
  // Default setting for end of clip will stop playback
  
  self.playedToEndBlock = ^{
    NSLog(@"GPUVFrameSourceVideo.playedToEndBlock %.3f", CACurrentMediaTime());
    [weakSelf stop];
  };

  [self setLoadedBlockCallbacks];
  
  // Async logic to parse M4V headers to get tracks and other metadata.
  // Note that this logic returns player1 in the init case.

  self.isPlayer2Active = TRUE;
  GPUVPlayerVideoOutput *pvo = [self preloadNextItem];
  self.isPlayer2Active = FALSE;

  NSAssert(pvo.player, @"player");

  AVAsset *asset = pvo.playerItem.asset;
  NSAssert(asset, @"curent item asset is nil");
  
  [self startAsyncTracksLoad:asset pvo:pvo];

  return TRUE;
}

- (void) startAsyncTracksLoad:(AVAsset*)asset
                      pvo:(GPUVPlayerVideoOutput*)pvo
{
  __weak typeof(self) weakSelf = self;
  __weak typeof(pvo) weakPvo = pvo;
  
  NSArray *assetKeys = @[@"duration", @"playable", @"tracks"];
  
  if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded)
  {
    BOOL worked = [self asyncTracksReady:asset pvo:pvo];
    
    // Need to preroll start once we know the async tracke loading
    // was successful
    
    if (worked == FALSE) {
      // In the failed to load case, invoke callback
      if (weakSelf.loadedBlock != nil) {
        weakSelf.loadedBlock(FALSE);
        //weakSelf.loadedBlock = nil;
      }
    }
    
    return;
  }
  
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
      dispatch_async(dispatch_get_main_queue(), ^{
        BOOL worked = [weakSelf asyncTracksReady:asset pvo:weakPvo];
        
        if (worked == FALSE) {
          // In the failed to load case, invoke callback
          if (weakSelf.loadedBlock != nil) {
            weakSelf.loadedBlock(FALSE);
            //weakSelf.loadedBlock = nil;
          }
        }
      });
    }
    
  }];
}


// FIXME: is it possible that async callback could be too late, pass
// original ref so that a race condition cannot happen.

// Async callback that is invoked when the "tracks" property has been
// loaded and is ready to be inspected.

- (BOOL) asyncTracksReady:(AVAsset*)asset
                      pvo:(GPUVPlayerVideoOutput*)pvo
{
  NSLog(@"asyncTracksReady");
  
  // Verify that the status for this specific key is ready to be read
  
#if defined(DEBUG)
  // Callback must be processed on main thread
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  [pvo asyncTracksReady:asset];
  return TRUE;
}

- (AVPlayerItem*) grabFirstQueueItemAndRotate
{
  // Rotate queueItems[0] to the end of the queue
  AVPlayerItem *firstItem = self.queueItems[0];
  [self.queueItems addObject:firstItem];
  [self.queueItems removeObjectAtIndex:0];
#if defined(DEBUG)
  NSAssert(firstItem, @"firstItem");
  NSAssert(firstItem != self.queueItems[0], @"firstItem");
#endif // DEBUG
  return firstItem;
}

// Begin loading the next item by configuring AVPlayerItem
// and associating it with AVPlayer. Note that this method
// does not switch the next item to the active item

- (GPUVPlayerVideoOutput*) preloadNextItem
{
  AVPlayerItem *firstItem = [self grabFirstQueueItemAndRotate];
  
  GPUVPlayerVideoOutput *pvo = [self getNextPlayerVideoOutput];
  NSAssert(pvo, @"pvo");
  
//  if (pvo.player == nil) {
//    // Init player
//    pvo.player = [[AVPlayer alloc] init];
//  } else {
//  }
  
  AVPlayer *player = pvo.player;
  
  if (player == nil) {
    pvo.player = [[AVPlayer alloc] init];
  }
  
  pvo.playerItem = firstItem;
  
  return pvo;
}

- (GPUVPlayerVideoOutput*) advanceToNextItem
{
  // Switch to other player
  self.isPlayer2Active = ! self.isPlayer2Active;
  
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  
  // Rotate queueItems[0] to the end of the queue
  AVPlayerItem *firstItem = [self grabFirstQueueItemAndRotate];
  
//  if (pvo.player == nil) {
//    // Init player
//    pvo.player = [[AVPlayer alloc] init];
//  } else {
//  }
  
  // Nil out ref inside old player if it is defined
  
  AVPlayer *player = pvo.player;
  
  if (player == nil) {
    pvo.player = [[AVPlayer alloc] init];
  }
  
//  if (player) {
//    [player replaceCurrentItemWithPlayerItem:nil];
//  }
  
  //pvo.player = [[AVPlayer alloc] init];
  
  pvo.playerItem = firstItem;

  return pvo;
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

  CFTimeInterval syncTime = CACurrentMediaTime();
  [self play:syncTime];
}

- (void) stop
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  // Configure player layer now that asset tracks is loaded
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  [pvo stop];
}

// restart will rewind and then play, in the case where the video is already
// playing then a call to restart will just rewind.

- (void) restart {
  NSLog(@"restart");
  
  // Halt playback of current item
  
  {
    GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
    [pvo endOfLoop];
  }
  
  // Advance to next item
  
  GPUVPlayerVideoOutput *pvo = [self advanceToNextItem];
  
  AVAsset *asset = pvo.playerItem.asset;
  NSAssert(asset, @"curent item asset is nil");
  
  [self startAsyncTracksLoad:asset pvo:pvo];
}

// Define a CMTimescale that will be used by the player, this
// implicitly assumes that the timeline has a rate of 0.0
// and that the caller will start playback by setting the
// timescale rate.

- (void) useMasterClock:(CMClockRef)masterClock
{
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  [pvo useMasterClock:masterClock];
}

- (void) seekToTimeZero
{
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  [pvo seekToTimeZero];
}

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block
{
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  [pvo playWithPreroll:rate block:block];
}

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime
{
  GPUVPlayerVideoOutput *pvo = [self getCurrentPlayerVideoOutput];
  [pvo syncStart:rate itemTime:itemTime atHostTime:atHostTime];
}

// Invoked after a player has loaded an asset and is ready to play

- (void) loadedCallback:(BOOL)success
{
  self.width = self.playerVideoOutput1.width;
  self.height = self.playerVideoOutput1.height;
  
  self.FPS = self.playerVideoOutput1.FPS;
  self.frameDuration = self.playerVideoOutput1.frameDuration;
  
  if (self.loadedBlock != nil) {
    self.loadedBlock(success);
    //self.loadedBlock = nil;
  }
}

@end
