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

@end
