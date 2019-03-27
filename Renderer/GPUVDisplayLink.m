//
//  GPUVDisplayLink.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVDisplayLink.h"

//#define LOG_DISPLAY_LINK_TIMINGS

// Private API

@interface GPUVDisplayLink ()

#if TARGET_OS_IOS
@property (nonatomic, retain) CADisplayLink *displayLink;
#else
// Hold active ref to object passed to display link callback
@property (nonatomic, retain) NSObject *displayLinkHoldref;
#endif // TARGET_OS_IOS

// Once media data has been prerolled and vsync timing is available
// then the view can begin to render data from a video source.

@property (nonatomic, assign) BOOL isReadyToPlay;

// The last N display link vsync events will be tracked with this array.

@property (nonatomic, retain) NSMutableArray *displayLinkVsyncTimes;

// If sync start special case is needed then these fields are used to
// wait until a couple of vsyncs are delivered.
@property (nonatomic, retain) NSTimer *syncStartTimer;

// The previous host time when decode callback is invoked on the main
// thread.

@property (nonatomic, assign) CFTimeInterval prevDecodeHostTime;

// When a frame is decoded, the time that this frame should be displayed
// is defined in terms of the vsync frame time.

@property (nonatomic, assign) CFTimeInterval presentationTime;

#if TARGET_OS_IOS
// nop
#else // TARGET_OS_IOS

- (void)displayLinkCallback:(CFTimeInterval)frameTime displayAt:(CFTimeInterval)displayTime;
#endif // TARGET_OS_IOS

@end

#if !TARGET_OS_IPHONE

@interface DisplayLinkPrivateInterface : NSObject

// Ref to the view the display link is associated with

@property (atomic, weak) GPUVDisplayLink *weakSelf;

@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) CFTimeInterval vsyncDuration;

@property (nonatomic, assign) NSUInteger numVsyncCounter;

@property (nonatomic, assign) NSUInteger numVsyncStepsInFrameDuration;

@end

// Implementation DisplayLinkPrivateInterface

@implementation DisplayLinkPrivateInterface

- (void) dealloc
{
  if ((0)) {
    NSLog(@"dealloc %@", self);
  }
  return;
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"DisplayLinkPrivateInterface %p : GPUVDisplayLink %p", self, self.weakSelf];
}

@end // end DisplayLinkPrivateInterface

static CVReturn displayLinkRenderCallback(CVDisplayLinkRef displayLink,
                                          const CVTimeStamp *inNow,
                                          const CVTimeStamp *inOutputTime,
                                          CVOptionFlags flagsIn,
                                          CVOptionFlags *flagsOut,
                                          void *displayLinkContext)
{
  @autoreleasepool {
    DisplayLinkPrivateInterface *displayLinkPrivateInterface = (__bridge DisplayLinkPrivateInterface *) displayLinkContext;
    GPUVDisplayLink *displayLinkWeakSelf = displayLinkPrivateInterface.weakSelf;
    
    const int debugPrintAll = 0;
    const int debugPrintDeliveredToMainThread = 0;
    
    // FIXME: Need to address thread safety for each of these properties,
    // all properties should be set inside a single lock on self.
    
    // If view was deallocated before display link fires then nop
    
    if (displayLinkWeakSelf == nil) {
      if (debugPrintAll) {
        printf("weakSelf is nil, nop\n");
      }
      return kCVReturnSuccess;
    }
    
    // Calculate numVsyncCounter
    
    if (displayLinkPrivateInterface.numVsyncStepsInFrameDuration == 0)
    {
      CVTime displayLinkVsyncDuration = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink);
      CFTimeInterval displayLinkVsyncDurationSeconds = ((float)displayLinkVsyncDuration.timeValue) / displayLinkVsyncDuration.timeScale;
      
      if (debugPrintAll) {
        printf("displayLinkVsyncDuration %0.3f : AKA %0.2f FPS\n", displayLinkVsyncDurationSeconds, 1.0f / displayLinkVsyncDurationSeconds);
      }
      
      CFTimeInterval numVsyncStepsInFrameDuration = displayLinkPrivateInterface.frameDuration / displayLinkVsyncDurationSeconds;
      
      // 3.000001 -> 3
      // 3.1      -> 4
      
      double fractPart = numVsyncStepsInFrameDuration - floor(numVsyncStepsInFrameDuration);
      
      NSUInteger numSteps = 0;
      
      if (fractPart >= 0.1) {
        numSteps = (NSUInteger) floor(numVsyncStepsInFrameDuration) + 1;
      } else {
        numSteps = (NSUInteger) round(numVsyncStepsInFrameDuration);
      }
      
      displayLinkPrivateInterface.numVsyncStepsInFrameDuration = numSteps;
      
      if (displayLinkPrivateInterface.numVsyncStepsInFrameDuration == 0) {
        displayLinkPrivateInterface.numVsyncStepsInFrameDuration = 1;
      }
      
      if (debugPrintAll) {
        printf("numVsyncStepsInFrameDuration %0.2f : round() to %d vsyncs\n", numVsyncStepsInFrameDuration, (int)displayLinkPrivateInterface.numVsyncStepsInFrameDuration);
      }

      displayLinkPrivateInterface.vsyncDuration = displayLinkVsyncDurationSeconds;
      
      displayLinkPrivateInterface.numVsyncCounter = 0;
    }
    
    CFTimeInterval hostFrequency = CVGetHostClockFrequency();
    CFTimeInterval nowSeconds = inNow->hostTime / hostFrequency;
    
    // Output time indicates when vsync should be executed
    
    CFTimeInterval outSeconds = inOutputTime->hostTime / hostFrequency;

    CFTimeInterval frameSeconds = 0.0;
    CFTimeInterval displaySeconds = 0.0;
    
    if (debugPrintAll)
    {
      printf("displayLinkVsyncDuration at Video NOW            %.6f\n", nowSeconds);
      printf("displayLinkVsyncDuration at Video OUT            %.6f\n", outSeconds);
      printf("duration                          NOW -> OUT     %.6f\n", outSeconds-nowSeconds);
    }
    
    BOOL deliverToMainThread = FALSE;
    
    if (displayLinkPrivateInterface.numVsyncCounter == 0) {
      displayLinkPrivateInterface.numVsyncCounter = displayLinkPrivateInterface.numVsyncStepsInFrameDuration;
    }
    
    // If there is just 1 vsync or this is the first vsync interval in a series
    // of N vsyncs then deliver a draw to the main thread.
    
    if (displayLinkPrivateInterface.numVsyncCounter == displayLinkPrivateInterface.numVsyncStepsInFrameDuration) {
      deliverToMainThread = TRUE;
      
      // Calculate "decode time", this is 1/2 way between "frame" durations
      // which can include multiple vsync intervals. The goal here is to get
      // a host time to pass into the video frame display layer that is
      // as far away from the frame change at the start or end of the interval
      // as possible.
      
      float frameDuration = (displayLinkPrivateInterface.vsyncDuration * displayLinkPrivateInterface.numVsyncStepsInFrameDuration);
      float halfFrameDuration = 0.5f * frameDuration;
      frameSeconds = outSeconds - halfFrameDuration;
      
      if (debugPrintAll)
      {
        printf("outSeconds     %.6f\n", outSeconds);
        printf("frame times    [%.6f %.6f]\n", outSeconds-frameDuration, outSeconds);
        printf("frameSeconds   %.6f\n", frameSeconds);
      }

      if (displayLinkPrivateInterface.numVsyncStepsInFrameDuration == 1) {
        // 60 FPS
        displaySeconds = outSeconds;
      } else {
        // 30 FPS or slower, frame time is halfway to next vsync
        int N = (int) (displayLinkPrivateInterface.numVsyncStepsInFrameDuration - 1);
        displaySeconds = outSeconds + (N * displayLinkPrivateInterface.vsyncDuration);
      }
    }
    
    displayLinkPrivateInterface.numVsyncCounter -= 1;
    
    if (debugPrintAll)
    {
      printf("numVsyncCounter %d -> deliverToMainThread %d\n", (int)displayLinkPrivateInterface.numVsyncCounter, (int)deliverToMainThread);
      
      if (deliverToMainThread) {
        printf("frameSeconds   %.6f\n", frameSeconds);
        printf("displaySeconds %.6f\n", displaySeconds);
        printf("displaySeconds ahead of outSeconds %.6f\n", displaySeconds-outSeconds);
      }
    }
    
    if (debugPrintAll || debugPrintDeliveredToMainThread) {
      fflush(stdout);
    }
    
    // Send to main thread only when needed
    
    if (deliverToMainThread) {
      // FIXME: should this use dispatch_async() or dispatch_sync() so that display link thread is blocked?
      
      // dispatch_async()
      // dispatch_sync()
      dispatch_async(dispatch_get_main_queue(), ^{
#if defined(DEBUG)
        if (debugPrintAll) {
        printf("before displayLinkCallback in main thread CACurrentMediaTime() %.6f\n", CACurrentMediaTime());
        }
#endif // DEBUG
        
        GPUVDisplayLink *displayLinkWeakSelf = displayLinkPrivateInterface.weakSelf;
        [displayLinkWeakSelf displayLinkCallback:frameSeconds displayAt:displaySeconds];
      });
    }
  }
  
  return kCVReturnSuccess;
}
#endif

@implementation GPUVDisplayLink
{
#if TARGET_OS_IOS
  // nop
#else
  CVDisplayLinkRef _displayLink;
#endif // TARGET_OS_IOS
}

// FIXME: if view is deallocated while rendering then the render operation
// will need to finish before the view can be deallocated. Need to hold
// an active ref for long enough for a pending render operaiton to finish
// and then the view can be deallocated!

- (void) dealloc
{
//  [self cancelDisplayLink];
#if TARGET_OS_IOS
#else
  // Unlink DisplayLinkPrivateInterface weak ref back to view
  DisplayLinkPrivateInterface *displayLinkPrivateInterface = (DisplayLinkPrivateInterface *) self.displayLinkHoldref;
  displayLinkPrivateInterface.weakSelf = nil;
  self.displayLinkHoldref = nil;
#endif // TARGET_OS_IOS
  
  [self.syncStartTimer invalidate];
  self.syncStartTimer = nil;
  
  return;
}

- (NSString*) description
{
  int width = (int) -1;
  int height = (int) -1;
  
  return [NSString stringWithFormat:@"GPUVDisplayLink %p %dx%d",
          self,
          width,
          height];
}

// FIXME: Should display link interface be constant across different views?
// So, for example if 2 views are displaying videos that should be in sync
// then shoudl 1 shared display link object be used between the 2 views?
// Come back to this detail after splitting notification and init logic
// into a frame source module.

#pragma mark - DisplayLink

- (void) makeDisplayLink
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  float FPS = self.FPS;
  
#if defined(DEBUG)
  NSAssert(FPS != 0.0f, @"fps not set when creating display link");
#endif // DEBUG
  
  if ((0)) {
    // Force display link framerate that is 2x a 30 FPS interval,
    // this should not change the render result since a minimum
    // frame time is indicated with each render present operation.
    FPS = 60;
  }
  
#if TARGET_OS_IOS
  // CADisplayLink
  
  assert(self.displayLink == nil);
  
  self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
  self.displayLink.paused = TRUE;
#else
  // nop
#endif // TARGET_OS_IOS
  
  // FIXME: configure preferredFramesPerSecond based on parsed FPS from video file
  
  //self.displayLink.preferredFramesPerSecond = FPS;
  
  //self.displayLink.preferredFramesPerSecond = 10;
  
  //float useFPS = (FPS * 10); // Force 10 FPS sampling rate when 1 FPS is detected
  
  float useFPS = FPS;
  
  // FIXME: What about a framerate like 23.98 ? Should round to 24 or use 30 FPS
  // sampling rate?
  
  NSInteger intFPS = (NSInteger) round(useFPS);
  
  if (intFPS < 1) {
    intFPS = 1;
  }
  
#if TARGET_OS_IOS
  self.displayLink.preferredFramesPerSecond = intFPS;
  
  // FIXME: what to pass as forMode? Should this be
  // NSRunLoopCommonModes cs NSDefaultRunLoopMode
  
  [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
#else
  // CVDisplayLink
  CGDirectDisplayID displayID = CGMainDisplayID();
  CVReturn error = CVDisplayLinkCreateWithCGDisplay(displayID, &_displayLink);
  if ( error ) {
    NSLog(@"DisplayLink created with error:%d", error);
    _displayLink = NULL;
  }

  // Note that this arguent does not hold a ref to the view which avoids ref count loop
  
  DisplayLinkPrivateInterface *displayLinkPrivateInterface = [[DisplayLinkPrivateInterface alloc] init];
  displayLinkPrivateInterface.weakSelf = self;
  
  displayLinkPrivateInterface.frameDuration = self.frameDuration;
  
  // Cannot be calculated until the first call
  
  displayLinkPrivateInterface.numVsyncCounter = 0;
  
  self.displayLinkHoldref = displayLinkPrivateInterface;
  CVDisplayLinkSetOutputCallback(_displayLink, displayLinkRenderCallback, (__bridge void *)displayLinkPrivateInterface);
#endif // TARGET_OS_IOS
}

// Note that this method is a nop if invoked when display link is already running

- (void) startDisplayLink
{
#if TARGET_OS_IOS
  if (self.displayLink.paused == TRUE) {
    self.displayLink.paused = FALSE;
    
    NSLog(@"loadedBlock : paused = FALSE : start display link at host time %.3f", CACurrentMediaTime());
  }
#else
  assert(_displayLink != NULL);
  
  if (CVDisplayLinkIsRunning(_displayLink) == FALSE) {
    CVDisplayLinkStart(_displayLink);
    
    NSLog(@"loadedBlock : paused = FALSE : start display link at host time %.3f", CACurrentMediaTime());
  }
#endif // TARGET_OS_IOS
}

- (void) cancelDisplayLink
{
#if TARGET_OS_IOS
  self.displayLink.paused = TRUE;
  [self.displayLink invalidate];
  self.displayLink = nil;
#else
  if ( !_displayLink ) return;
  CVDisplayLinkStop(_displayLink);
  CVDisplayLinkRelease(_displayLink);
  _displayLink = NULL;
#endif // TARGET_OS_IOS
}

- (BOOL) isDisplayLinkNotInitialized
{
#if TARGET_OS_IOS
  if (self.displayLink == nil) {
    return TRUE;
  }
#else
  if (_displayLink == NULL) {
    return TRUE;
  }
#endif // TARGET_OS_IOS

  return FALSE;
}

#if TARGET_OS_IOS
- (void)displayLinkCallback:(CADisplayLink*)displayLink
#else
- (void)displayLinkCallback:(CFTimeInterval)frameTime displayAt:(CFTimeInterval)displayTime
#endif // TARGET_OS_IOS
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  if ((0)) {
    NSLog(@"displayLinkCallback at host time %.3f", CACurrentMediaTime());
  }
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  CFTimeInterval framePresentationTime, hostTime, decodeTime;
  
  // hostTime is the previous vsync time plus the amount of time
  // between the vsync and the invocation of this callback. It is
  // tempting to use targetTimestamp as the time for the next
  // vsync except there is no way to "force" frame zero at
  // the start of the decoding process so then frame zero
  // will always be displayed at the time actually indicated
  // by targetTimestamp (assuming a frame is decoded there).
  // This will sync as long as all video data is 1 frame behind.
  
#if TARGET_OS_IOS
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  if ((1)) {
    CFTimeInterval prevFrameTime = displayLink.timestamp;
    CFTimeInterval nextFrameTime = displayLink.targetTimestamp;
    CFTimeInterval duration = nextFrameTime - prevFrameTime;
    
    NSLog(@"prev %0.3f -> next %0.3f : duration %0.2f : sender.duration %0.2f", prevFrameTime, nextFrameTime, duration, displayLink.duration);
    NSLog(@"");
  }
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  //CFTimeInterval hostTime = displayLink.timestamp + displayLink.duration;
  hostTime = (displayLink.timestamp + displayLink.targetTimestamp) * 0.5f;
  // Save next vsync time
  framePresentationTime = displayLink.targetTimestamp;

#if defined(LOG_DISPLAY_LINK_TIMINGS)
  NSLog(@"host half time %0.3f : offset from timestamp %0.3f", hostTime, hostTime-displayLink.timestamp);
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  // Record host time when this decode method is invoked
  
  decodeTime = displayLink.timestamp + displayLink.duration;
  
#else // TARGET_OS_IOS
  // MacOSX
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  if ((1)) {
    CFTimeInterval prevFrameTime = displayTime - self.frameDuration;
    CFTimeInterval nextFrameTime = displayTime;

    NSLog(@"frameTime   %0.3f", frameTime);
    NSLog(@"displayTime %0.3f", displayTime);
    NSLog(@"prev %0.3f -> next %0.3f : frameDuration %0.2f", prevFrameTime, nextFrameTime, nextFrameTime - prevFrameTime);
    NSLog(@"");
  }
#endif // LOG_DISPLAY_LINK_TIMINGS

  hostTime = frameTime;
  // Save next vsync time
  framePresentationTime = displayTime;
  
  decodeTime = frameTime;
#endif // TARGET_OS_IOS
  
  // Host time delta
  
  CFTimeInterval delta;
  if (self.prevDecodeHostTime == 0) {
    delta = 0;
  } else {
    delta = decodeTime - self.prevDecodeHostTime;
  }
  self.prevDecodeHostTime = decodeTime;
  
#if defined(LOG_DISPLAY_LINK_TIMINGS)
  NSLog(@"host delta from prev time %0.3f", delta);
#endif // LOG_DISPLAY_LINK_TIMINGS
  
  // Record timing info until the next vsync can be predicted
  
  NSMutableArray *displayLinkVsyncTimes = self.displayLinkVsyncTimes;
  
  if (self.displayLinkVsyncTimes == nil) {
    self.displayLinkVsyncTimes = [NSMutableArray array];
    displayLinkVsyncTimes = self.displayLinkVsyncTimes;
  }
  
  {
    NSNumber *framePresentationTimeNum = [NSNumber numberWithDouble:framePresentationTime];
    [displayLinkVsyncTimes addObject:framePresentationTimeNum];
    
    if (displayLinkVsyncTimes.count > 3) {
      [displayLinkVsyncTimes removeObjectAtIndex:0];
    }
  }

  if (self.isReadyToPlay == FALSE) {
#if defined(LOG_DISPLAY_LINK_TIMINGS)
    if ((1)) {
      NSLog(@"isReadyToPlay is FALSE");
    }
#endif // LOG_DISPLAY_LINK_TIMINGS
    
    return;
  }
  
  // FIXME: when the display link is firsh starting up, do not invoke
  // invocationBlock() until the display link is up and running.
  
  // Invoke callback block once 2 display link times have been reported
  
  if (self.invocationBlock != nil) {
    self.invocationBlock(hostTime, framePresentationTime);
  }
}

// This method is invoked when a video has been preloaded
// and the video is ready to sync start at a given host time.

- (void) syncStart:(CFTimeInterval)atHostTime
{
  // Note that loadedBlock must be invoked directly here
  // so that a host time in the future is processed in
  // the callback block in time to correct sync start the stream.
  // Do not schedule for future processing on the main
  // thread for example.
  
  if (self.loadedBlock != nil) {
    self.loadedBlock(atHostTime);
  }
}

- (void) syncStartCheck
{
  NSArray *displayLinkVsyncTimes = [NSArray arrayWithArray:self.displayLinkVsyncTimes];
  
  if (displayLinkVsyncTimes.count >= 1) {
    // At least 1 vsync times, ready to start
    
    [self.syncStartTimer invalidate];
    self.syncStartTimer = nil;
    
    self.isReadyToPlay = TRUE;
    
    NSNumber *vsyncNum = [displayLinkVsyncTimes lastObject];
    CFTimeInterval syncTime = [vsyncNum doubleValue];
    [self syncStart:syncTime];
  }
}

// This method is invoked once preroll on the video source
// has been completed. In the case where the video is ready
// to play and the display link is running then kick off
// playback in the view object. In the case where the video
// is ready to play but the display link is not running yet,
// wait until the display link is up and running.

- (void) checkReadyToPlay
{
  //NSLog(@"checkReadyToPlay playWithPreroll block");
  
  // The display link should be running, but there is a possible
  // race condition when the preroll completes before a display
  // link time has been delivered. The view will not actually
  // render until isReadyToPlay has been set to TRUE, so take
  // care of the race condition with a timer.
  
  // It should not be possible to kick off the timer twice
  
  //#if defined(DEBUG)
  NSAssert(self.syncStartTimer == nil, @"syncStartTimer is already set");
  //NSAssert(weakSelf.isReadyToPlay == FALSE, @"isReadyToPlay is already TRUE");
  //#endif // DEBUG
  
  NSArray *displayLinkVsyncTimes = [NSArray arrayWithArray:self.displayLinkVsyncTimes];
  
  if (displayLinkVsyncTimes.count < 1) {
    NSAssert(self.syncStartTimer == nil, @"syncStartTimer is already set");
    
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0f/60.0f
                                             target:self
                                           selector:@selector(syncStartCheck)
                                           userInfo:nil
                                            repeats:TRUE];
    
    self.syncStartTimer = timer;
    
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
  } else {
    // vSync times available sync item start to upcoming time
    
    self.isReadyToPlay = TRUE;
    
    NSNumber *vsyncNum = [displayLinkVsyncTimes lastObject];
    CFTimeInterval syncTime = [vsyncNum doubleValue];
    [self syncStart:syncTime];
  }
}

@end
