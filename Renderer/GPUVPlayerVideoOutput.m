//
//  GPUVPlayerVideoOutput.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
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
    // Looping over N assets and this is not the first asset.
    // Preload the player with asset metadata but do not
    // initiate playback.
    
//    dispatch_async(dispatch_get_main_queue(), ^{
//      float rate = weakSelf.playRate;
//      assert(rate != 0.0f);
//
//      [weakSelf playWithPreroll:rate block:^{
//        NSLog(@"secondaryLoopAsset playWithPreroll finished at time %.2f", CACurrentMediaTime());
//
//        weakSelf.isReadyToPlay = TRUE;
//        CFTimeInterval syncTime = weakSelf.syncTime;
//        float playRate = weakSelf.playRate;
//
//        //[weakSelf syncStart:playRate itemTime:0.0 atHostTime:syncTime];
//      }];
//    });
    
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
  NSLog(@"%p outputSequenceWasFlushed %p : output %p", self, self.playerItem, output);
  
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
    
    self.finalFrameTime = trackDuration - frameDurationSeconds - (frameDurationSeconds * 0.05);
    
    if (assetLogOutput) {
    NSLog(@"video finalFrameTime %.3f", self.finalFrameTime);
    }
  }
  
  {
    // Calculate load time, this is one second before the end of the clip

    //self.lastSecondFrameTime = trackDuration - 1.5;
    self.lastSecondFrameTime = trackDuration - 3.0;
    
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
    
    NSLog(@"OUTPUT init %p", playerItem);
  } else if (self.playerItem == playerItem) {
    // Activate the item that is currently active
    //[playerItem removeOutput:self.playerItemVideoOutput];
    //[playerItem addOutput:self.playerItemVideoOutput];
    
    //NSLog(@"OUTPUT remove/add %p -> %p", playerItem, playerItem);
    
    NSLog(@"OUTPUT NOP same item %p", playerItem);
  } else {
    assert(0);
    
    // Changing the item connected to the video output
#if defined(DEBUG)
    NSAssert(playerItem != self.playerItem, @"playerItem != self.playerItem");
#endif // DEBUG
    [self.playerItem removeOutput:self.playerItemVideoOutput];
    if (1) {
      // FIXME: Destroy the old output and create a new one ??
    }
    [playerItem addOutput:self.playerItemVideoOutput];
    NSLog(@"OUTPUT changed remove/add %p -> %p", self.playerItem, playerItem);
    self.playerItem = playerItem;
    
    // Resync current item time to next frame sync time
    
    //[self seekToTimeZero];
    //[self setRate:self.playRate atHostTime:self.syncTime];
    //NSLog(@"Player setRate with current time %.3f", CMTimeGetSeconds(self.player.currentTime));
    
    [self syncStart:self.playRate itemTime:0.0 atHostTime:self.syncTime];
    
    //NSLog(@"incr loopCount from %d to %d", self.loopCount, self.loopCount+1);
    //self.loopCount = self.loopCount + 1;
  }
  
  // Kick off preroll from main thread but do not actually start playback at this point.
  // When there is sufficient time between the preroll and the time when playback actually begins
  // then async loading from asset will happen and the video should be ready to play at t = 0.0
  
  if (self.secondaryLoopAsset) {
    float playRate = self.playRate;
    assert(playRate != 0.0f);
    
    __weak typeof(self) weakSelf = self;
    
    [self playWithPreroll:playRate block:^{
      NSLog(@"secondaryLoopAsset playWithPreroll finished at time %.3f", CACurrentMediaTime());
      
      weakSelf.isReadyToPlay = TRUE;
      //CFTimeInterval syncTime = weakSelf.syncTime;
      //[weakSelf syncStart:playRate itemTime:0.0 atHostTime:syncTime];
      
      if (self.asyncReadyToPlayBlock != nil) {
        self.asyncReadyToPlayBlock();
        self.asyncReadyToPlayBlock = nil;
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
  NSAssert(self.addedObservers == TRUE, @"observer must have been added");
  
  //if (self.addedObservers == FALSE) {
    __weak typeof(self) weakSelf = self;
    [self removeObserver:weakSelf forKeyPath:@"player.currentItem.status" context:AVPlayerItemStatusContext];
  //}
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
        NSLog(@"AVPlayerItemStatusReadyToPlay %p", self);
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
  //[self.playerItem removeOutput:self.playerItemVideoOutput];
  
  self.playerItemVideoOutput = nil;
  
  // FIXME: Instead of invoking setRate or pause here, could the player AVPlayerActionAtItemEnd
  // value for player.actionAtItemEnd be set to AVPlayerActionAtItemEndPause ?
  
  [self.player setRate:0.0];
}

- (void) stop
{
  self.isPlaying = FALSE;
  self.isReadyToPlay = FALSE;
  
  [self unregisterForItemNotificaitons];
  
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
  
  [self seekToTimeZero];
  
  NSLog(@"AVPlayer playWithPreroll : %.2f : starting at time %.3f", rate, CACurrentMediaTime());
  
  //self.loopCount = 0;
  
  player.automaticallyWaitsToMinimizeStalling = FALSE;
  
  [player prerollAtRate:rate completionHandler:^(BOOL finished){
    // FIXME: Should finished be passed to block to cancel?
    // FIXME: Should pass rate to block
    
    NSLog(@"AVPlayer playWithPreroll finished at time %.3f", CACurrentMediaTime());
    
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
    NSLog(@"GPUVPlayerVideoOutput:setRate : at %.3f : with item time %.3f", atHostTime, CMTimeGetSeconds(self.player.currentTime));
  }
  
  CMTime hostTimeCM = CMTimeMake(atHostTime * 1000.0f, 1000);
  [self.player setRate:rate time:kCMTimeInvalid atHostTime:hostTimeCM];
  if (rate == 0) {
    // setRate(0) will stop playback
    self.isPlaying = FALSE;
  } else {
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
