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

static void *AVPlayerItemStatusContext = &AVPlayerItemStatusContext;

// Private API

@interface GPUVFrameSourceVideo ()

// Player instance objects to decode CoreVideo buffers from an asset item

@property (nonatomic, retain) AVPlayer *player;
@property (nonatomic, retain) AVPlayerItem *playerItem;
@property (nonatomic, retain) AVPlayerItemVideoOutput *playerItemVideoOutput;
@property (nonatomic, retain) dispatch_queue_t playerQueue;

@property (nonatomic, assign) int frameNum;

@end

@implementation GPUVFrameSourceVideo
{
    id _notificationToken;
}

- (void) dealloc
{
  return;
}

- (NSString*) description
{
  int width = self.width;
  int height = self.height;
  
  return [NSString stringWithFormat:@"GPUVFrameSourceVideo %p %dx%d ",
          self,
          width,
          height];
}

// Given a host time offset, return a GPUVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.

- (GPUVFrame*) frameForHostTime:(CFTimeInterval)hostTime
{
  if (self.player.currentItem == nil) {
    NSLog(@"player not playing yet in frameForHostTime");
    return nil;
  }

  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
  
#define LOG_DISPLAY_LINK_TIMINGS
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  if ((1)) {
    NSLog(@"frameForHostTime at host time %.3f", CACurrentMediaTime());
  }
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  // Map time offset to item time
  
  CMTime currentItemTime = [playerItemVideoOutput itemTimeForHostTime:hostTime];
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  NSLog(@"host time %0.3f -> item time %0.3f", hostTime, CMTimeGetSeconds(currentItemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS

  if ([playerItemVideoOutput hasNewPixelBufferForItemTime:currentItemTime]) {
    // Grab the pixel bufer for the current time
    
    CVPixelBufferRef rgbPixelBuffer = [playerItemVideoOutput copyPixelBufferForItemTime:currentItemTime itemTimeForDisplay:NULL];
    
    if (rgbPixelBuffer != NULL) {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
      NSLog(@"LOADED RGB frame for item time %0.3f", CMTimeGetSeconds(currentItemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
      
      GPUVFrame *nextFrame = [[GPUVFrame alloc] init];
      nextFrame.yCbCrPixelBuffer = rgbPixelBuffer;
      CVPixelBufferRelease(rgbPixelBuffer);
      return nextFrame;
    } else {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
      NSLog(@"did not load RGB frame for item time %0.3f", CMTimeGetSeconds(currentItemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
    }
  } else {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
    NSLog(@"hasNewPixelBufferForItemTime is FALSE at vsync time %0.3f", CMTimeGetSeconds(currentItemTime));
#endif // LOG_DISPLAY_LINK_TIMINGS
  }
  
  return nil;
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
  self.player = [[AVPlayer alloc] init];
  
  self.playerItem = [AVPlayerItem playerItemWithURL:URL];
  
  NSLog(@"PlayerItem URL %@", URL);
  
  NSDictionary *pixelBufferAttributes = [BGRAToBT709Converter getPixelBufferAttributes];
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionaryWithDictionary:pixelBufferAttributes];
  
  // Add kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
  
  mDict[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  
  pixelBufferAttributes = [NSDictionary dictionaryWithDictionary:mDict];
  
  self.playerItemVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];;
  
  // FIXME: does this help ?
  self.playerItemVideoOutput.suppressesPlayerRendering = TRUE;
  
  self.playerQueue = dispatch_queue_create("com.decodem4v.carspin_rgb", DISPATCH_QUEUE_SERIAL);
  
  __weak GPUVFrameSourceVideo *weakSelf = self;
  
  [self.playerItemVideoOutput setDelegate:weakSelf queue:self.playerQueue];
  
#if defined(DEBUG)
  assert(self.playerItemVideoOutput.delegateQueue == self.playerQueue);
#endif // DEBUG
  
  //self.frameNum = 0;
  
  // @"CarSpin_alpha.m4v"
  
  
  // Async logic to parse M4V headers to get tracks and other metadata
  
  AVAsset *asset = [self.playerItem asset];
  
  NSArray *assetKeys = @[@"duration", @"playable", @"tracks"];
  
  [asset loadValuesAsynchronouslyForKeys:assetKeys completionHandler:^{
    
    // FIXME: Save @"duration" when available here
    
    // FIXME: if @"playable" is FALSE then need to return error and not attempt to play
    
    if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
      NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
      if ([videoTracks count] > 0) {
        // Choose the first video track. Ignore other tracks if found
        const int videoTrackOffset = 0;
        AVAssetTrack *videoTrack = [videoTracks objectAtIndex:videoTrackOffset];
        
        // Must be self contained
        
        if (videoTrack.isSelfContained != TRUE) {
          //NSLog(@"videoTrack.isSelfContained must be TRUE for \"%@\"", movPath);
          //return FALSE;
          assert(0);
        }
        
        CGSize itemSize = videoTrack.naturalSize;
        NSLog(@"video track naturalSize w x h : %d x %d", (int)itemSize.width, (int)itemSize.height);
        
        // Allocate render buffer once asset dimensions are known
        
        {
          // FIXME: how would a queue player that has multiple outputs with different asset sizes be handled
          // here? Would intermediate render buffers be different sizes?
          
          dispatch_sync(dispatch_get_main_queue(), ^{
            GPUVFrameSourceVideo *strongSelf = weakSelf;
            if (strongSelf) {
              // Writing to this property must be done on main thread
              //strongSelf.resizeTextureSize = itemSize;
              strongSelf.width = (int) itemSize.width;
              strongSelf.height = (int) itemSize.height;
            }
            
            //[weakSelf makeInternalMetalTexture];
          });
        }
        
        CMTimeRange timeRange = videoTrack.timeRange;
        float trackDuration = (float)CMTimeGetSeconds(timeRange.duration);
        NSLog(@"video track time duration %0.3f", trackDuration);
        
        CMTime frameDurationTime = videoTrack.minFrameDuration;
        float frameDuration = (float)CMTimeGetSeconds(frameDurationTime);
        NSLog(@"video track frame duration %0.3f", frameDuration);
        
        {
          GPUVFrameSourceVideo *strongSelf = weakSelf;
          if (strongSelf) {
            // Once display frame interval has been parsed, create display
            // frame timer but be sure it is created on the main thread
            // and that this method invocation completes before the
            // next call to dispatch_async() to start playback.
            
            // FIXME: get closest known FPS time ??
            float frameDurationSeconds = CMTimeGetSeconds(frameDurationTime);
            
            dispatch_sync(dispatch_get_main_queue(), ^{
              // Note that writing to FPS members must be executed on the
              // main thread.
              
              strongSelf.FPS = frameDurationSeconds;
              
              //[weakSelf makeDisplayLink];
            });
          }
        }
        
        float nominalFrameRate = videoTrack.nominalFrameRate;
        NSLog(@"video track nominal frame duration %0.3f", nominalFrameRate);
        
        // FIXME: Do not automatically start playback here, deliver
        // a notification that everything is ready to go and wait for
        // view or media object to start playback.
        
        float ONE_FRAME_DURATION = 1.0f / 10.0f;
        
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf.playerItem addOutput:weakSelf.playerItemVideoOutput];
          [weakSelf.player replaceCurrentItemWithPlayerItem:weakSelf.playerItem];
          [weakSelf addDidPlayToEndTimeNotificationForPlayerItem:weakSelf.playerItem];
          [weakSelf.playerItem seekToTime:kCMTimeZero completionHandler:nil];
          [weakSelf.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:ONE_FRAME_DURATION];
//          [weakSelf.player play];
          //weakSelf.loadedBlock(TRUE);
        });
      }
    }
    
  }];
  
  return TRUE;
}

// Kick of play operation

- (void) play
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  [self.player play];
  
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
  dispatch_async(dispatch_get_main_queue(), ^{
    self.loadedBlock(TRUE);    
    self.loadedBlock = nil;
  });
  
  NSLog(@"outputMediaDataWillChange");
  
  return;
}

- (void) regiserForItemNotificaitons
{
  [self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:AVPlayerItemStatusContext];
}

- (void) unregiserForItemNotificaitons
{
  [self removeObserver:self forKeyPath:@"player.currentItem.status" context:AVPlayerItemStatusContext];
}

- (void) addDidPlayToEndTimeNotificationForPlayerItem:(AVPlayerItem *)item
{
  if (_notificationToken) {
    _notificationToken = nil;
  }
  
  // Setting actionAtItemEnd to None prevents the movie from getting paused at item end. A very simplistic, and not gapless, looped playback.
  
  _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
  _notificationToken = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
    // Simple item playback rewind.
    [self.playerItem seekToTime:kCMTimeZero completionHandler:nil];
  }];
}

- (void) unregisterForItemEndNotification
{
  if (_notificationToken) {
    [[NSNotificationCenter defaultCenter] removeObserver:_notificationToken name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
    _notificationToken = nil;
  }
}

- (void)outputSequenceWasFlushed:(AVPlayerItemOutput*)output
{
  NSLog(@"outputSequenceWasFlushed");
  
  return;
}

// Wait for video dimensions to be come available

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (context == AVPlayerItemStatusContext) {
    AVPlayerStatus status = [change[NSKeyValueChangeNewKey] integerValue];
    switch (status) {
      case AVPlayerItemStatusUnknown:
        break;
      case AVPlayerItemStatusReadyToPlay: {
        //        CGSize itemSize = [[self.player currentItem] presentationSize];
        //        NSLog(@"AVPlayerItemStatusReadyToPlay: video itemSize dimensions : %d x %d", (int)itemSize.width, (int)itemSize.height);
        //        _resizeTextureSize = itemSize;
        //        [self makeInternalMetalTexture];
        break;
      }
      case AVPlayerItemStatusFailed: {
        //[self stopLoadingAnimationAndHandleError:[[_player currentItem] error]];
        NSLog(@"AVPlayerItemStatusFailed : %@", [[self.player currentItem] error]);
        break;
      }
    }
  }
  else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

@end
