/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
//#import "AAPLShaderTypes.h"
//
//#import "MetalRenderContext.h"
//#import "MetalBT709Decoder.h"
//#import "MetalScaleRenderContext.h"
//#import "BGRAToBT709Converter.h"
//#import "BGDecodeEncode.h"
//#import "CGFrameBuffer.h"
//#import "CVPixelBufferUtils.h"
//
//#import "GPUVFrame.h"
//#import "GPUVMTKView.h"

@interface AAPLRenderer ()

@end

// Main class performing the rendering
@implementation AAPLRenderer
{
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
  self = [super init];
  if(self) {
  }
  return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    //_viewportSize.x = size.width;
    //_viewportSize.y = size.height;
  
    NSLog(@"drawableSizeWillChange %d x %d", (int)size.width, (int)size.height);
}

@end
