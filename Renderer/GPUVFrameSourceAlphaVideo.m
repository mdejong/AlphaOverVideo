//
//  GPUVFrameSourceAlphaVideo.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVFrameSourceAlphaVideo.h"

//#define STORE_TIMES

// Private API

@interface GPUVFrameSourceVideo ()

@property (nonatomic, retain) AVPlayer *player;
@property (nonatomic, retain) AVPlayerItemVideoOutput *playerItemVideoOutput;
@property (nonatomic, assign) int frameNum;

@end

// Private API

@interface GPUVFrameSourceAlphaVideo ()

@property (nonatomic, retain) GPUVFrameSourceVideo *rgbSource;
@property (nonatomic, retain) GPUVFrameSourceVideo *alphaSource;

@property (nonatomic, assign) BOOL rgbSourceLoaded;
@property (nonatomic, assign) BOOL alphaSourceLoaded;

@property (nonatomic, retain) GPUVFrame *heldRGBFrame;
@property (nonatomic, retain) GPUVFrame *heldAlphaFrame;

#if defined(STORE_TIMES)
@property (nonatomic, retain) NSMutableArray *times;
#endif // STORE_TIMES

@end

@implementation GPUVFrameSourceAlphaVideo

- (void) dealloc
{
  //NSLog(@"%@", self);
  
  return;
}

- (NSString*) description
{
  int width = self.width;
  int height = self.height;
  
  return [NSString stringWithFormat:@"GPUVFrameSourceAlphaVideo %p %dx%d ",
          self,
          width,
          height];
}

// Given a host time offset, return a GPUVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.

- (GPUVFrame*) frameForHostTime:(CFTimeInterval)hostTime
           hostPresentationTime:(CFTimeInterval)hostPresentationTime
            presentationTimePtr:(float*)presentationTimePtr
{
  const int debugDumpForHostTimeValues = 1;
  
#if defined(STORE_TIMES)
  if (self.times == nil) {
    self.times = [NSMutableArray array];
  }
  
  NSMutableArray *timeArr = [NSMutableArray array];
#endif // STORE_TIMES
  
  // Dispatch a host time to both sources and decode a frame for each one.
  // If a given time does not load a new frame for both sources then
  // the RGB and Alpha decoding is not in sync and the frame must be dropped.
  
//  if (debugDumpForHostTimeValues) {
//  NSLog(@"rgb and alpha frameForHostTime %.3f", hostTime);
//  }
  
  self.syncTime = hostPresentationTime;
  
  GPUVFrameSourceVideo *rgbSource = self.rgbSource;
  GPUVFrameSourceVideo *alphaSource = self.alphaSource;
  
  CMTime itemTime = [rgbSource itemTimeForHostTime:hostTime];

  if ((0)) {
    NSLog(@"%@ : frameForHostTime at host time %.3f : CACurrentMediaTime() %.3f", self, hostTime, CACurrentMediaTime());
    NSLog(@"item time %.3f", CMTimeGetSeconds(itemTime));
  }
  
  GPUVFrame *rgbFrame = nil;
  GPUVFrame *alphaFrame = nil;

#if defined(DEBUG)
  if (self.heldRGBFrame) {
    NSAssert(self.heldAlphaFrame == nil, @"heldAlphaFrame");
  }
  if (self.heldAlphaFrame) {
    NSAssert(self.heldRGBFrame == nil, @"heldRGBFrame");
  }
#endif // DEBUG
  
  BOOL isHeldOver = FALSE;
  BOOL isRGBHeldOver = FALSE;
  BOOL isAlphaHeldOver = FALSE;
  
  float rgbPresentaitonTime = -1;
  float alphaPresentaitonTime = -1;
  
  if (self.heldRGBFrame != nil) {
    rgbFrame = self.heldRGBFrame;
    self.heldRGBFrame = nil;
    isHeldOver = TRUE;
    isRGBHeldOver = TRUE;
  } else {
    rgbFrame = [rgbSource frameForItemTime:itemTime hostTime:hostTime hostPresentationTime:hostPresentationTime presentationTimePtr:&rgbPresentaitonTime];
  }
  
  // Note the case where RGB has already failed to load a frame, do not
  // the load alpha frame in this case.
  
  if (self.heldAlphaFrame != nil) {
    alphaFrame = self.heldAlphaFrame;
    self.heldAlphaFrame = nil;
    isHeldOver = TRUE;
    isAlphaHeldOver = TRUE;
  } else if (rgbFrame != nil) {
    alphaFrame = [alphaSource frameForItemTime:itemTime hostTime:hostTime hostPresentationTime:hostPresentationTime presentationTimePtr:&alphaPresentaitonTime];
  }
  
#if defined(DEBUG)
  NSAssert(self.heldAlphaFrame == nil, @"heldAlphaFrame");
  NSAssert(self.heldRGBFrame == nil, @"heldRGBFrame");
#endif // DEBUG
  
  int rgbFrameNum = (rgbFrame == nil) ? -1 : rgbFrame.frameNum;
  int alphaFrameNum = (alphaFrame == nil) ? -1 : alphaFrame.frameNum;
  
  if (debugDumpForHostTimeValues) {
  NSLog(@"rgbFrameNum %d : alphaFrameNum %d", rgbFrameNum, alphaFrameNum);
  }
  
  const BOOL isHeldOverLogging = TRUE;
  
  if (isHeldOver) {
    if (rgbFrameNum == alphaFrameNum) {
      if (isHeldOverLogging) {
        NSLog(@"isHeldOver REPAIRED");
      }
    } else if (rgbFrameNum != alphaFrameNum) {
      if (isHeldOverLogging) {
        NSLog(@"isHeldOver mismatch with %d != %d", rgbFrameNum, alphaFrameNum);
        NSLog(@"");
      }

      // If the held over frame is behind the frame that was just decoded, then
      // decode from the hel over stream with the current item time to determine
      // if this would repair the jitter.
      
      if (rgbFrameNum != -1 && alphaFrameNum != -1) {
        if (isRGBHeldOver) {
          rgbFrame = [rgbSource frameForItemTime:itemTime hostTime:hostTime hostPresentationTime:hostPresentationTime presentationTimePtr:&rgbPresentaitonTime];
          rgbFrameNum = (rgbFrame == nil) ? -1 : rgbFrame.frameNum;
        } else if (isAlphaHeldOver) {
          alphaFrame = [alphaSource frameForItemTime:itemTime hostTime:hostTime hostPresentationTime:hostPresentationTime presentationTimePtr:&alphaPresentaitonTime];
          alphaFrameNum = (alphaFrame == nil) ? -1 : alphaFrame.frameNum;
        }
        
        if (rgbFrameNum == alphaFrameNum) {
          if (isHeldOverLogging) {
            NSLog(@"isHeldOver REPAIRED stage2 : %d == %d", rgbFrameNum, alphaFrameNum);
          }
        } else {
          if (isHeldOverLogging) {
            NSLog(@"isHeldOver NOT REPAIRED stage2 : %d != %d", rgbFrameNum, alphaFrameNum);
          }
        }
      }
    }
  }
  
#if defined(STORE_TIMES)
  // Media time when this frame data is being processed, ahead of hostTime since
  // the hostTime value is determined in relation to vsync bounds.
  [timeArr addObject:@(CACurrentMediaTime())];  
  [timeArr addObject:@(hostTime)];
  [timeArr addObject:@(CMTimeGetSeconds(itemTime))];
  
  [timeArr addObject:@(rgbPresentaitonTime)];
  [timeArr addObject:@(rgbFrameNum)];
  [timeArr addObject:@(alphaPresentaitonTime)];
  [timeArr addObject:@(alphaFrameNum)];
#endif // STORE_TIMES
  
  if (rgbFrame == nil && alphaFrame == nil) {
    // No frame avilable from either source
    if (isHeldOverLogging) {
      NSLog(@"no decoded RGB or Alpha frame");
    }
    rgbFrame = nil;
  } else if (rgbFrame != nil && alphaFrame == nil) {
    // RGB returned a frame but alpha did not
    if (isHeldOverLogging) {
      NSLog(@"RGB returned a frame but alpha did not");
    }
    rgbFrame = nil;
  } else if (rgbFrame == nil && alphaFrame != nil) {
    // alpha returned a frame but RGB did not
    if (isHeldOverLogging) {
      NSLog(@"alpha returned a frame but RGB did not");
    }
    rgbFrame = nil;
  } else if (rgbFrameNum != alphaFrameNum) {
    if (isHeldOverLogging) {
    NSLog(@"rgbFrameNum %d : alphaFrameNum %d", rgbFrameNum, alphaFrameNum);
    NSLog(@"RGB vs Alpha decode frame mismatch");
    }
    
    // case A: rgb = 2 alpha = 3
    // case B: rgb = 3, alpha = 2
    // anything else, drop frame
    
    BOOL offByOne = FALSE;
    
    if (rgbFrameNum+1 == alphaFrameNum) {
      // Hold alpha until next loop
      self.heldAlphaFrame = alphaFrame;
      offByOne = TRUE;
    } else if (alphaFrameNum+1 == rgbFrameNum) {
      // Hold rgb until next loop
      self.heldRGBFrame = rgbFrame;
      offByOne = TRUE;
    }
    
    if (offByOne) {
      if (isHeldOverLogging) {
        NSLog(@"setRate to repair frame off by 1 mismatch");
      }

      // Resync the current playback time to the time halfway
      // through the interval, in many cases this will repair
      // the issue where the two tracks are just slightly off

      [self setRate:self.playRate atHostTime:hostTime];
    }

    rgbFrame = nil;
  } else {
    rgbFrame.alphaPixelBuffer = alphaFrame.yCbCrPixelBuffer;
    alphaFrame = nil;
  }
  
#if defined(STORE_TIMES)
  [self.times addObject:timeArr];
#endif // STORE_TIMES
  
  if (presentationTimePtr != NULL) {
    *presentationTimePtr = rgbPresentaitonTime;
  }

  return rgbFrame;
}

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been decoded.

- (BOOL) hasMoreFrames;
{
  return TRUE;
}

// Init pair of video source objects

- (void) makeSources
{
  self.rgbSource = [[GPUVFrameSourceVideo alloc] init];
  self.alphaSource = [[GPUVFrameSourceVideo alloc] init];
  
  self.rgbSource.uid = @"rgb";
  self.alphaSource.uid = @"alpha";
}

// Init from pair of asset names

- (BOOL) loadFromAssets:(NSString*)resFilename alphaResFilename:(NSString*)resAlphaFilename
{
  [self makeSources];
  
  BOOL worked;
  
  worked = [self.rgbSource loadFromAsset:resFilename];
  
  if (worked) {
    worked = [self.alphaSource loadFromAsset:resAlphaFilename];
  }
  
  // redefine finished callbacks
  
  [self setBothLoadCallbacks];
  
  return worked;
}

// Init from asset or remote URL

- (BOOL) loadFromURLs:(NSURL*)URL alphaURL:(NSURL*)alphaURL
{
  [self makeSources];
  
  BOOL worked;
  
  worked = [self.rgbSource loadFromURL:URL];
  
  if (worked) {
    worked = [self.alphaSource loadFromURL:alphaURL];
  }
  
  return worked;
}

// FIXME: both callbacks need to report in and pass successfully,
// return error conditions if not both successful after waiting
// for both to be invoked.

- (void) setBothLoadCallbacks
{
  __weak typeof(self) weakSelf = self;
  weakSelf.rgbSourceLoaded = FALSE;
  weakSelf.alphaSourceLoaded = FALSE;
  
  self.rgbSource.loadedBlock = ^(BOOL success) {
    if (!success) {
      if (weakSelf.loadedBlock != nil) {
        weakSelf.loadedBlock(FALSE);
        weakSelf.loadedBlock = nil;
      }
      return;
    }
    
    weakSelf.rgbSourceLoaded = TRUE;
    
    if (weakSelf.alphaSourceLoaded) {
      [weakSelf bothLoaded];
    } else {
//      if (weakSelf.loadedBlock != nil) {
//        weakSelf.loadedBlock(FALSE);
//        weakSelf.loadedBlock = nil;
//      }
    }
  };
  
  self.alphaSource.loadedBlock = ^(BOOL success) {
    if (!success) {
      if (weakSelf.loadedBlock != nil) {
        weakSelf.loadedBlock(FALSE);
        weakSelf.loadedBlock = nil;
      }
      return;
    }
    
    weakSelf.alphaSourceLoaded = TRUE;
    
    if (weakSelf.rgbSourceLoaded) {
      [weakSelf bothLoaded];
    } else {
//      if (weakSelf.loadedBlock != nil) {
//        weakSelf.loadedBlock(FALSE);
//        weakSelf.loadedBlock = nil;
//      }
    }
  };
  
  // Implement seamless looping by restarting just after
  // the final frame has been decoded and displayed.
  
  self.rgbSource.playedToEndBlock = nil;
  self.alphaSource.playedToEndBlock = nil;
  
  self.rgbSource.finalFrameBlock = ^{
    NSLog(@"self.rgbSource.finalFrameBlock %.3f", CACurrentMediaTime());
    [weakSelf restart];
  };
  
  self.alphaSource.finalFrameBlock = nil;
  
  return;
}

// Invoked once both videos have been successfully loaded

- (void) bothLoaded
{
  self.FPS = self.rgbSource.FPS;
  self.frameDuration = self.rgbSource.frameDuration;
  
  // FPS must match
  
  float alphaFPS = self.alphaSource.FPS;
  
  int intFPS = (int)round(self.FPS);
  int intAlphaFPS = (int)round(alphaFPS);
  
  // FIXME: Provide reporting structure that includes an error code and string
  
  if (intFPS != intAlphaFPS) {
    assert(0);
  }
  
  // width and height must match
  
  self.frameDuration = self.rgbSource.frameDuration;
  
  self.width = self.rgbSource.width;
  self.height = self.rgbSource.height;
  
  int alphaWidth = self.alphaSource.width;
  int alphaHeight = self.alphaSource.height;
  
  if (self.width != alphaWidth) {
    assert(0);
  }
  if (self.height != alphaHeight) {
    assert(0);
  }
  
  // FIXME: validate that FPS, width x height are the same for both videos
  
  self.loadedBlock(TRUE);
  self.loadedBlock = nil;
}

// Preroll with callback block

- (void) playWithPreroll:(float)rate block:(void (^)(void))block
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  self.playRate = rate;
  
  // FIXME: Need a block that waits for a callback to be
  // invoked for each source, then the user supplied block
  // gets invoked once to kick off the play op.
  
  __block BOOL wait1Finished = FALSE;
  __block BOOL wait2Finished = FALSE;
  
  void (^waitBlock1)(void) = ^{
    wait1Finished = TRUE;
    if (wait2Finished) {
      block();
    }
  };
  
  void (^waitBlock2)(void) = ^{
    wait2Finished = TRUE;
    if (wait1Finished) {
      block();
    }
  };
  
  [self.rgbSource playWithPreroll:rate block:waitBlock1];
  [self.alphaSource playWithPreroll:rate block:waitBlock2];
}

// Invoke player setRate to actually begin playing back a video
// source once playWithPreroll invokes the block callback
// with a specific host time to sync to.

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime
{
  [self.rgbSource setRate:rate atHostTime:atHostTime];
  [self.alphaSource setRate:rate atHostTime:atHostTime];
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
    [self.rgbSource play];
    [self.alphaSource play];
  } else if ((1)) {
    CFTimeInterval hostTime = CACurrentMediaTime();
    
    [self.rgbSource seekToTimeZero];
    [self.alphaSource seekToTimeZero];
    
    [self.rgbSource play:hostTime];
    [self.alphaSource play:hostTime];
  } else {
    // Assign same master clock to both players
    
    CFTimeInterval hostTime = CACurrentMediaTime();
    
    CMClockRef hostTimeMasterClock = CMClockGetHostTimeClock();
    [self useMasterClock:hostTimeMasterClock];
    
    [self.rgbSource play:hostTime];
    [self.alphaSource play:hostTime];
  }
}

- (void) useMasterClock:(CMClockRef)masterClock
{
  [self.rgbSource useMasterClock:masterClock];
  [self.alphaSource useMasterClock:masterClock];
}

- (void) stop
{
  [self.rgbSource stop];
  [self.alphaSource stop];
}

- (void) seekToTimeZero
{
  [self.rgbSource seekToTimeZero];
  [self.alphaSource seekToTimeZero];
}

- (void) restart {
  //[self.rgbSource restart];
  //[self.alphaSource restart];
  
  self.rgbSource.numRestarts += 1;
  
//  if (self.rgbSource.numRestarts > 2) {
//    ;
//  }
  
  self.heldRGBFrame = nil;
  self.heldAlphaFrame = nil;
  
  CFTimeInterval syncTime = self.syncTime;
  float playRate = self.playRate;
  
  [self.rgbSource seekToTimeZero];
  [self.alphaSource seekToTimeZero];
  
  [self.rgbSource setRate:playRate atHostTime:syncTime];
  [self.alphaSource setRate:playRate atHostTime:syncTime];
}

@end
