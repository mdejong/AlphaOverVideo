//
//  MetalScaleRenderContext.h
//
//  Copyright 2019 Mo DeJong.
//
//  See license.txt for license terms.
//
//  This module will render into an existing MTKView
//  in the case where a 2D rescale operation is needed
//  to fit the contents of a Metal texture into a view.

//@import MetalKit;
#import <MetalKit/MetalKit.h>

@class MetalRenderContext;

NS_ASSUME_NONNULL_BEGIN

@interface MetalScaleRenderContext : NSObject

// Name of fragment shader function

@property (nonatomic, copy, nonnull) NSString *fragmentFunction;

// fragment pipeline

@property (nonatomic, retain) id<MTLRenderPipelineState> pipelineState;

// Setup render pixpeline to render into the given view.

- (void) setupRenderPipelines:(MetalRenderContext*)mrc
                      mtkView:(MTKView*)mtkView;

// Render into MTKView with 2D scale operation

- (BOOL) renderScaled:(MetalRenderContext*)mrc
              mtkView:(nonnull MTKView *)mtkView
          renderWidth:(int)renderWidth
         renderHeight:(int)renderHeight
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
 renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
          bgraTexture:(id<MTLTexture>)bgraTexture;

@end

NS_ASSUME_NONNULL_END

