//
//  GPUVFrameSourceAlphaVideo.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVFrameSourceAlphaVideo.h"

//#import <QuartzCore/QuartzCore.h>

// Private API

@interface GPUVFrameSourceAlphaVideo ()

@property (nonatomic, retain) GPUVFrameSourceVideo *rgbSource;
@property (nonatomic, retain) GPUVFrameSourceVideo *alphaSource;

@property (nonatomic, assign) BOOL rgbSourceLoaded;
@property (nonatomic, assign) BOOL alphaSourceLoaded;

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
  // Dispatch a host time to both sources and decode a frame for each one.
  // If a given time does not load a new frame for both sources then
  // the RGB and Alpha decoding is not in sync and the frame must be dropped.
  
  GPUVFrame *rgbFrame = [self.rgbSource frameForHostTime:hostTime];
  GPUVFrame *alphaFrame = [self.alphaSource frameForHostTime:hostTime];

  int rgbFrameNum = [GPUVFrame calcFrameNum:rgbFrame.yCbCrPixelBuffer];
  int alphaFrameNum = [GPUVFrame calcFrameNum:alphaFrame.yCbCrPixelBuffer];  
  NSLog(@"rgbFrameNum %d : alphaFrameNum %d", rgbFrameNum, alphaFrameNum);

  if (rgbFrame == nil && alphaFrame == nil) {
    // No frame avilable from either source
    return nil;
  } else if (rgbFrame != nil && alphaFrame == nil) {
    // RGB returned a frame but alpha did not
    NSLog(@"RGB returned a frame but alpha did not");
    return nil;
  } else if (rgbFrame == nil && alphaFrame != nil) {
    // alpha returned a frame but RGB did not
    NSLog(@"alpha returned a frame but RGB did not");
    return nil;
  } else {
    rgbFrame.alphaPixelBuffer = alphaFrame.yCbCrPixelBuffer;
    alphaFrame = nil;
    return rgbFrame;
  }
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
  
  [self setBothLoadCallbacks];
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

// Kick of play operation

- (void) play
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  if ((0)) {
    [self.rgbSource play];
    [self.alphaSource play];
  } else {
    CFTimeInterval hostTime = CACurrentMediaTime();
    [self.rgbSource play:hostTime];
    [self.alphaSource play:hostTime];
  }
}

@end
