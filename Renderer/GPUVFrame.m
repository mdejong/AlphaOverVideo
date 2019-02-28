//
//  GPUVFrame.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVFrame.h"

#import <QuartzCore/QuartzCore.h>

// Private API

@interface GPUVFrame ()

@end

@implementation GPUVFrame

@synthesize yCbCrPixelBuffer = m_yCbCrPixelBuffer;
@synthesize alphaPixelBuffer = m_alphaPixelBuffer;

// Setter for self.yCbCrPixelBuffer, this logic holds on to a retain for the CoreVideo buffer

- (void) setYCbCrPixelBuffer:(CVPixelBufferRef)cvBufferRef
{
  if (cvBufferRef) {
    CFRetain(cvBufferRef);
  }
  if (self->m_yCbCrPixelBuffer) {
    CFRelease(self->m_yCbCrPixelBuffer);
  }
  self->m_yCbCrPixelBuffer = cvBufferRef;
}

- (void) setAlphaPixelBuffer:(CVPixelBufferRef)cvBufferRef
{
  if (cvBufferRef) {
    CFRetain(cvBufferRef);
  }
  if (self->m_alphaPixelBuffer) {
    CFRelease(self->m_alphaPixelBuffer);
  }
  self->m_alphaPixelBuffer = cvBufferRef;
}

- (void) dealloc
{
  self.yCbCrPixelBuffer = nil;
  self.alphaPixelBuffer = nil;
  return;
}

- (NSString*) description
{
  int width = (int) CVPixelBufferGetWidth(self.yCbCrPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(self.yCbCrPixelBuffer);
  
  int rgbRetainCount = 0;
  int alphaRetainCount = 0;
  
  if (self.yCbCrPixelBuffer != NULL) {
    rgbRetainCount = (int)CFGetRetainCount(self.yCbCrPixelBuffer);
  }
  
  if (self.alphaPixelBuffer != NULL) {
    alphaRetainCount = (int)CFGetRetainCount(self.alphaPixelBuffer);
  }

  return [NSString stringWithFormat:@"GPUVFrame %p %dx%d self.yCbCrPixelBuffer %p (%d) self.alphaPixelBuffer %p (%d)",
          self,
          width,
          height,
          self.yCbCrPixelBuffer,
          rgbRetainCount,
          self.alphaPixelBuffer,
          alphaRetainCount];
}

+ (int) calcFrameNum:(CVPixelBufferRef)cvPixelBuffer
{
  if (cvPixelBuffer == NULL) {
    return -1;
  }
  
  NSDictionary *movieTimeDict = (__bridge NSDictionary *) CVBufferGetAttachment(cvPixelBuffer, kCVBufferMovieTimeKey, NULL);
  
//  2 : <CFString 0x1dd16ad88 [0x1dcbfd5e0]>{contents = "QTMovieTime"} = <CFBasicHash 0x282f2bf40 [0x1dcbfd5e0]>{type = mutable dict, count = 2,
//    entries =>
//    0 : <CFString 0x1dd16ada8 [0x1dcbfd5e0]>{contents = "TimeValue"} = <CFNumber 0xf3e5608b93a8a324 [0x1dcbfd5e0]>{value = +0, type = kCFNumberSInt64Type}
//    1 : <CFString 0x1dd16adc8 [0x1dcbfd5e0]>{contents = "TimeScale"} = <CFNumber 0xf3e5608b93a89da5 [0x1dcbfd5e0]>{value = +1000, type = kCFNumberSInt32Type}
//  }
  
  NSNumber *timeValueNum = movieTimeDict[@"TimeValue"];
  NSNumber *timeScaleNum = movieTimeDict[@"TimeScale"];
  
  float timeValue = [timeValueNum floatValue];
  float timeScale = [timeScaleNum floatValue];
  
  float frameNum = timeValue / timeScale;
  
  return (int) round(frameNum);
}

@end
