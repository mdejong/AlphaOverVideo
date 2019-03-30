//
//  GPUVPlayerVideoOutput.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//

#import "GPUVPlayerVideoOutput.h"

#import "BGRAToBT709Converter.h"

static void *AVPlayerItemStatusContext = &AVPlayerItemStatusContext;

// Private API

@interface GPUVPlayerVideoOutput ()

@property (nonatomic, assign) BOOL addedObservers;

@end

@implementation GPUVPlayerVideoOutput

- (void) dealloc
{
  [self.playerItemVideoOutput setDelegate:nil queue:nil];
  self.playerQueue = nil;
  return;
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"GPUVPlayerVideoOutput %p", self];
}

// Util method that creates AVPlayerItemVideoOutput instance

- (void) makeVideoOutput {
  NSAssert(self.playerItemVideoOutput == nil, @"playerItemVideoOutput");
  
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

#pragma mark - AVPlayerItemOutputPullDelegate

// FIXME: Need to mark state to indicate that media has been
// parsed and is now ready to play. But, cannot directly
// operate on a displayLink here since there is not a 1 to 1
// mapping between a display link and an output. A callback
// into the view or some other type of notification will
// be needed to signal that the media is ready to play.

- (void)outputMediaDataWillChange:(AVPlayerItemOutput*)sender
{
#if defined(DEBUG)
  // Callback must be processed on main thread
  
  NSAssert([NSThread isMainThread] == FALSE, @"!isMainThread");
#endif // DEBUG
  
  NSLog(@"outputMediaDataWillChange : GPUVPlayerVideoOutput %p", self);
  
  __weak typeof(self) weakSelf = self;
  
  // FIXME: should this send back up to parent once swapped over
  // to the active player ?

  if (self.secondaryLoopAsset) {
    // nop    
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.isReadyToPlay = TRUE;
      
      if (weakSelf.loadedBlock != nil) {
        weakSelf.loadedBlock(TRUE);
        //weakSelf.loadedBlock = nil;
      }
    });
  }
  
  return;
}


- (void)outputSequenceWasFlushed:(AVPlayerItemOutput*)output
{
  //NSLog(@"%p outputSequenceWasFlushed %p : output %p", self, self.playerItem, output);
  
  return;
}

// This method is invoked when the "tracks" data has become ready

// Async callback that is invoked when the "tracks" property has been
// loaded and is ready to be inspected.

- (BOOL) asyncTracksReady:(AVAsset*)asset
{
  const BOOL assetLogOutput = FALSE;
  
  if (assetLogOutput) {
  NSLog(@"asyncTracksReady with AVAsset %p", asset);
  }
  
  // Verify that the status for this specific key is ready to be read
  
#if defined(DEBUG)
  // Callback must be processed on main thread
  
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  
  AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:nil];
  NSAssert(status == AVKeyValueStatusLoaded, @"status != AVKeyValueStatusLoaded : %d", (int)status);
  
  NSAssert(self.isAssetAsyncLoaded == FALSE, @"isAssetAsyncLoaded");
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
  if (assetLogOutput) {
  NSLog(@"video track naturalSize w x h : %d x %d", (int)itemSize.width, (int)itemSize.height);
  }
  
  // Allocate render buffer once asset dimensions are known
  
  // Writing to this property must be done on main thread
  self.width = (int) itemSize.width;
  self.height = (int) itemSize.height;
  
  CMTimeRange timeRange = videoTrack.timeRange;
  float trackDuration = (float)CMTimeGetSeconds(timeRange.duration);
  if (assetLogOutput) {
  NSLog(@"video track time duration %0.3f", trackDuration);
  }
  
  CMTime frameDurationTime = videoTrack.minFrameDuration;
  float frameDurationSeconds = (float)CMTimeGetSeconds(frameDurationTime);
  if (assetLogOutput) {
  NSLog(@"video track frame duration %0.3f", frameDurationSeconds);
  }
  
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
  }
  
  {
    // Calculate the frame number of the final frame
    
    self.finalFrameTime = trackDuration - frameDurationSeconds;
    
    if (assetLogOutput) {
    NSLog(@"video finalFrameTime %.3f", self.finalFrameTime);
    }
  }
  
  {
    // Calculate load time, this is 1-3 seconds before the end of the clip
    // unless the frame duration is very long and then more preroll time
    // is required.

    float lastSecondFrameDelta = self.lastSecondFrameDelta;
    if (lastSecondFrameDelta == 0) {
      lastSecondFrameDelta = 3.0;
    }
    if (self.FPS < 15) {
      lastSecondFrameDelta = self.frameDuration * 6;
      self.lastSecondFrameDelta = lastSecondFrameDelta;
    }
    self.lastSecondFrameTime = trackDuration - lastSecondFrameDelta;
    
    if (assetLogOutput) {
    NSLog(@"video lastSecondFrameTime %.3f", self.lastSecondFrameTime);
    }
  }
  
  // Init player with current item, seek to time = 0.0
  // but do not start playback automatically
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
  if (assetLogOutput) {
  NSLog(@"video track nominal frame duration %0.3f", nominalFrameRate);
  }
  
  self.isAssetAsyncLoaded = TRUE;
  
  return TRUE;
}

// This method should be invoked when an async loaded asset is associated
// with the player.

- (void) assetReadyToPlay
{
#if defined(DEBUG)
  // Callback must be processed on main thread
    NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
    NSAssert(self.isAssetAsyncLoaded == TRUE, @"isAssetAsyncLoaded");
#endif // DEBUG
  
  BOOL newOutputCreated = FALSE;
  
  if (self.playerItemVideoOutput == nil) {
    // First invocation
    
    [self makeVideoOutput];
    
    newOutputCreated = TRUE;
    
    // FIXME: should this drive loading callabck with delay when not the first time
    // it is invoked?
    
    //[self.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
  }
  
  if (self.secondaryLoopAsset) {
  } else {
    // Deliver flush operation to secondary thread after one frame
  
    if (newOutputCreated) {
      // Always deliver event that kics off load block as async method
      [self.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
    }
  }
  
  AVPlayerItem *playerItem = self.player.currentItem;
  
  // In some cases, this method can be invoked when only a
  // single item is in the queue, since the one that was just
  // display has not been appened to the back of the item
  // queue again.
  
  // if (self.playerItem == nil) {
  
  if (newOutputCreated) {
    // Init case, add output and set
    [playerItem addOutput:self.playerItemVideoOutput];
    //self.playerItem = playerItem;
    
#if defined(DEBUG)
    NSLog(@"OUTPUT init %p", playerItem);
#endif // DEBUG
  } else if (self.playerItem == playerItem) {
    // Activate the item that is currently active
    //[playerItem removeOutput:self.playerItemVideoOutput];
    //[playerItem addOutput:self.playerItemVideoOutput];
    
    //NSLog(@"OUTPUT remove/add %p -> %p", playerItem, playerItem);
    
#if defined(DEBUG)
    NSLog(@"OUTPUT NOP same item %p", playerItem);
#endif // DEBUG
  } else {
    assert(0);
  }
  
  // Kick off preroll from main thread but do not actually start playback at this point.
  // When there is sufficient time between the preroll and the time when playback actually begins
  // then async loading from asset will happen and the video should be ready to play at t = 0.0
  
  if (self.secondaryLoopAsset) {
    float playRate = self.playRate;
#if defined(DEBUG)
    assert(playRate != 0.0f);
#endif // DEBUG
    
    __weak typeof(self) weakSelf = self;
    
    [self playWithPreroll:playRate block:^{
#if defined(DEBUG)
      NSLog(@"%p secondaryLoopAsset playWithPreroll finished at time %.3f", weakSelf, CACurrentMediaTime());
#endif // DEBUG
      
      weakSelf.isReadyToPlay = TRUE;
      
      if (weakSelf.asyncReadyToPlayBlock != nil) {
        weakSelf.asyncReadyToPlayBlock();
        weakSelf.asyncReadyToPlayBlock = nil;
      } else {
#if defined(DEBUG)
        NSLog(@"%p secondaryLoopAsset asyncReadyToPlayBlock is nil", weakSelf);
#endif // DEBUG
      }
    }];
    
  } else {
  }

  //self.isReadyToPlay = TRUE;
  return;
}

- (void) registerForItemNotificaitons
{
  NSAssert(self.addedObservers == FALSE, @"already added observer");
  __weak typeof(self) weakSelf = self;
  [self addObserver:weakSelf forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:AVPlayerItemStatusContext];
  self.addedObservers = TRUE;
  self.isAssetAsyncLoaded = FALSE;
}

- (void) unregisterForItemNotificaitons
{
  if (self.addedObservers == TRUE) {
    __weak typeof(self) weakSelf = self;
    [self removeObserver:weakSelf forKeyPath:@"player.currentItem.status" context:AVPlayerItemStatusContext];
  }
  self.addedObservers = FALSE;
}

// Wait for video dimensions to be come available

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if ((0)) {
    NSLog(@"observeValueForKeyPath \"%@\" %@", keyPath, change);
  }
  
  if (context == AVPlayerItemStatusContext) {
    AVPlayerStatus status = (AVPlayerStatus) AVPlayerItemStatusUnknown;
    NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
    if ([statusNumber isKindOfClass:[NSNumber class]]) {
      status = statusNumber.integerValue;
    }
    switch (status) {
      case AVPlayerItemStatusUnknown: {
        break;
      }
      case AVPlayerItemStatusReadyToPlay: {
#if defined(DEBUG)
        NSLog(@"AVPlayerItemStatusReadyToPlay %p", self);
#endif // DEBUG
        [self asyncTracksReady:self.player.currentItem.asset];
        [self assetReadyToPlay];
        break;
      }
      case AVPlayerItemStatusFailed: {
        NSLog(@"AVPlayerItemStatusFailed : %@", [self.playerItem error]);
        // FIXME: stop playback on error, need to pass up to enclosing scope
        break;
      }
    }
  }
  else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void) endOfLoop
{
  self.isPlaying = FALSE;
  self.isReadyToPlay = FALSE;
  
  [self unregisterForItemNotificaitons];
  
  //[self.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
 
  // Invoking removeOutput seems to make looping miss 2 frames
  
  // [self.playerItem removeOutput:self.playerItemVideoOutput];
  
//  AVPlayerItem *playerItem = self.playerItem;
//  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
//
//  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
//    [playerItem removeOutput:playerItemVideoOutput];
//  });
  
  self.playerItem = nil;
  self.playerItemVideoOutput = nil;

  // FIXME: Instead of invoking setRate or pause here, could the player AVPlayerActionAtItemEnd
  // value for player.actionAtItemEnd be set to AVPlayerActionAtItemEndPause ?
  
  [self.player setRate:0.0];
}

- (void) stop
{
  self.isPlaying = FALSE;
  self.isReadyToPlay = FALSE;

  self.secondaryLoopAsset = FALSE;
  
  [self unregisterForItemNotificaitons];
  
  //AVPlayerItem *playerItem = self.playerItem;
  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
  
  [playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:self.frameDuration];
  
  //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
  // [playerItem removeOutput:playerItemVideoOutput];
  //});
  
  self.playerItem = nil;
  self.playerItemVideoOutput = nil;
  
  [self.player setRate:0.0];
}

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  NSAssert(rate > 0.0, @"rate is %.3f", rate);
#endif // DEBUG
  
  self.playRate = rate;
  
  // Sync item time 0.0 to supplied host time (system clock)
  
  AVPlayer *player = self.player;
  
  [self seekToTimeZero];
  
#if defined(DEBUG)
  NSLog(@"%p AVPlayer playWithPreroll : %.2f : starting at time %.3f", self, rate, CACurrentMediaTime());
#endif // DEBUG
  
  //self.loopCount = 0;
  
  player.automaticallyWaitsToMinimizeStalling = FALSE;
  
  [player prerollAtRate:rate completionHandler:^(BOOL finished){
    // FIXME: Should finished be passed to block to cancel?
    // FIXME: Should pass rate to block
    
#if defined(DEBUG)
    NSLog(@"%p AVPlayer playWithPreroll finished at time %.3f", self, CACurrentMediaTime());
#endif // DEBUG
    
    if (finished) {
      block();
    }
  }];
}

// Sync start will seek to the given time and then invoke
// a sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  NSAssert(rate > 0.0, @"rate is %.3f", rate);
  NSAssert(self.isAssetAsyncLoaded == TRUE, @"isAssetAsyncLoaded must be TRUE when syncStart in invoked");
  NSAssert(self.isReadyToPlay == TRUE, @"isReadyToPlay must be TRUE when syncStart in invoked");
#endif // DEBUG
  
  self.secondaryLoopAsset = FALSE;
  
  CMTime syncTimeCM = CMTimeMake(itemTime * 1000.0f, 1000);
  [self.player seekToTime:syncTimeCM completionHandler:^(BOOL finished){
    if (finished) {
      CMTime hostTimeCM = CMTimeMake(atHostTime * 1000.0f, 1000);
      [self.player setRate:rate time:kCMTimeInvalid atHostTime:hostTimeCM];
      
#if defined(DEBUG)
      NSAssert(self.isAssetAsyncLoaded == TRUE, @"isAssetAsyncLoaded must be TRUE when syncStart in invoked");
#endif // DEBUG
      self.isPlaying = TRUE;
    }
  }];
}

// Invoke player setRate to actually begin playing back a video
// source once playWithPreroll invokes the block callback
// with a specific host time to sync to. Note that this API
// always uses the current time as the sync point.

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime
{
  if ((0)) {
    NSLog(@"GPUVPlayerVideoOutput:setRate : sync %.3f to item time %.3f", atHostTime, CMTimeGetSeconds(self.player.currentTime));
  }
  
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  NSAssert(rate > 0.0, @"rate is %.3f", rate);
  NSAssert(self.isAssetAsyncLoaded == TRUE, @"isAssetAsyncLoaded must be TRUE when setRate in invoked");
  NSAssert(self.isReadyToPlay == TRUE, @"isReadyToPlay must be TRUE when setRate in invoked");
  // Note that self.isPlaying could be true since setRate can be invoked to
  // resync a pair of streams that are already playing.
#endif // DEBUG
  
  CMTime hostTimeCM = CMTimeMake(atHostTime * 1000.0f, 1000);
  [self.player setRate:rate time:kCMTimeInvalid atHostTime:hostTimeCM];
  if (rate == 0) {
    // setRate(0) will stop playback
    self.isPlaying = FALSE;
  } else {
#if defined(DEBUG)
    NSAssert(self.isAssetAsyncLoaded == TRUE, @"isAssetAsyncLoaded must be TRUE when setRate in invoked");
#endif // DEBUG
    self.isPlaying = TRUE;
    self.playRate = rate;
  }
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
  
  self.secondaryLoopAsset = FALSE;
  
  // Sync item time 0.0 to supplied host time (system clock)
  
  AVPlayerItem *item = self.player.currentItem;
  
  NSLog(@"AVPlayer play sync itemTime 0.0 to %.3f", syncTime);
  
  self.player.automaticallyWaitsToMinimizeStalling = FALSE;
  CMTime hostTimeCM = CMTimeMake(syncTime * 1000.0f, 1000);
  [self.player setRate:self.playRate time:kCMTimeInvalid atHostTime:hostTimeCM];
  
  NSLog(@"play AVPlayer.item %d / %d : %0.3f", (int)item.currentTime.value, (int)item.currentTime.timescale, CMTimeGetSeconds(item.currentTime));
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
