//
//  GPUVFrameSourceAlphaVideo.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVFrameSourceAlphaVideo.h"

//#import <QuartzCore/QuartzCore.h>

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

@property (nonatomic, assign) BOOL rgbSourceEnded;
@property (nonatomic, assign) BOOL alphaSourceEnded;

#if defined(STORE_TIMES)
@property (nonatomic, retain) NSMutableArray *times;
#endif // STORE_TIMES

@end

@implementation GPUVFrameSourceAlphaVideo

- (void) dealloc
{
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
  
  if (debugDumpForHostTimeValues) {
  NSLog(@"rgb and alpha frameForHostTime %.3f", hostTime);
  }
  
  // FIXME: Split rgb and alpha frame read so that if no frame can be read for
  // the rgb channel then a read on the alpha channel is not executed.
  // Might also be useful to calculate the host time for the RGB and Alpha
  // streams first and then skip reading both frames if one of the two
  // is more than a frame off the other.
  
  GPUVFrameSourceVideo *rgbSource = self.rgbSource;
  GPUVFrameSourceVideo *alphaSource = self.alphaSource;
  
  GPUVFrame *rgbFrame = [rgbSource frameForHostTime:hostTime];
  GPUVFrame *alphaFrame = [alphaSource frameForHostTime:hostTime];

  if (debugDumpForHostTimeValues) {
  NSLog(@"check rgbFrameNum and alphaFrameNum");
  }
  
  int rgbFrameNum = [GPUVFrame calcFrameNum:rgbFrame.yCbCrPixelBuffer frameDuration:rgbSource.frameDuration];
  int alphaFrameNum = [GPUVFrame calcFrameNum:alphaFrame.yCbCrPixelBuffer frameDuration:alphaSource.frameDuration];
  
  if (debugDumpForHostTimeValues) {
  NSLog(@"rgbFrameNum %d : alphaFrameNum %d", rgbFrameNum, alphaFrameNum);
  }
  
#if defined(STORE_TIMES)
  // Media time when this frame data is being processed, ahead of hostTime since
  // the hostTime value is determined in relation to vsync bounds.
  [timeArr addObject:@(CACurrentMediaTime())];  
  [timeArr addObject:@(hostTime)];

  {
    AVPlayerItemVideoOutput *playerItemVideoOutput = rgbSource.playerItemVideoOutput;
    CMTime currentItemTime = [playerItemVideoOutput itemTimeForHostTime:hostTime];
  
    if ((0)) {
      NSLog(@"host time %0.3f -> item time %0.3f", hostTime, CMTimeGetSeconds(currentItemTime));
    }
    
    [timeArr addObject:@(CMTimeGetSeconds(currentItemTime))];
    [timeArr addObject:@(rgbFrameNum)];
  }

  {
    AVPlayerItemVideoOutput *playerItemVideoOutput = alphaSource.playerItemVideoOutput;
    CMTime currentItemTime = [playerItemVideoOutput itemTimeForHostTime:hostTime];
    
    if ((0)) {
      NSLog(@"host time %0.3f -> item time %0.3f", hostTime, CMTimeGetSeconds(currentItemTime));
    }

    [timeArr addObject:@(CMTimeGetSeconds(currentItemTime))];
    [timeArr addObject:@(alphaFrameNum)];
  }
#endif // STORE_TIMES
  
  if (rgbFrame == nil && alphaFrame == nil) {
    // No frame avilable from either source
    rgbFrame = nil;
  } else if (rgbFrame != nil && alphaFrame == nil) {
    // RGB returned a frame but alpha did not
    NSLog(@"RGB returned a frame but alpha did not");
    rgbFrame = nil;
  } else if (rgbFrame == nil && alphaFrame != nil) {
    // alpha returned a frame but RGB did not
    NSLog(@"alpha returned a frame but RGB did not");
    rgbFrame = nil;
  } else if (rgbFrameNum != alphaFrameNum) {
    if ((1)) {
    NSLog(@"rgbFrameNum %d : alphaFrameNum %d", rgbFrameNum, alphaFrameNum);
    NSLog(@"RGB vs Alpha decode frame mismatch");
    }
    rgbFrame = nil;
  } else {
    rgbFrame.alphaPixelBuffer = alphaFrame.yCbCrPixelBuffer;
    alphaFrame = nil;
  }
  
#if defined(STORE_TIMES)
  [self.times addObject:timeArr];
#endif // STORE_TIMES

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
  __weak GPUVFrameSourceAlphaVideo *weakSelf = self;
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
  
  // Set end of stream callbacks
  
  self.rgbSource.finishedBlock = ^{
    NSLog(@"self.rgbSource.finishedBlock");
    weakSelf.rgbSourceEnded = TRUE;
    if (weakSelf.rgbSourceEnded && weakSelf.alphaSourceEnded) {
      weakSelf.rgbSourceEnded = FALSE;
      weakSelf.alphaSourceEnded = FALSE;
      [weakSelf restart];
    }
  };
  
  self.alphaSource.finishedBlock = ^{
    NSLog(@"self.alphaSource.finishedBlock");
    weakSelf.alphaSourceEnded = TRUE;
    if (weakSelf.rgbSourceEnded && weakSelf.alphaSourceEnded) {
      weakSelf.rgbSourceEnded = FALSE;
      weakSelf.alphaSourceEnded = FALSE;
      [weakSelf restart];
    }
  };
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
  [self.rgbSource restart];
  [self.alphaSource restart];
}

@end
