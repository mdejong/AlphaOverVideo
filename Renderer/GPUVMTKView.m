//
//  GPUVMTKView.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//

#import "GPUVMTKView.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
//#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"
#import "MetalBT709Decoder.h"
#import "MetalScaleRenderContext.h"
#import "BGRAToBT709Converter.h"
#import "BGDecodeEncode.h"
#import "CGFrameBuffer.h"
#import "CVPixelBufferUtils.h"
#import "GPUVDisplayLink.h"

#define LOAD_ALPHA_VIDEO

#if defined(LOAD_ALPHA_VIDEO)
#import "GPUVFrameSourceAlphaVideo.h"
#else
#import "GPUVFrameSourceVideo.h"
#endif // LOAD_ALPHA_VIDEO

// Define this symbol to enable private texture mode on MacOSX.

//#define STORAGE_MODE_PRIVATE

static inline
void set_storage_mode(MTLTextureDescriptor *textureDescriptor)
{
#if defined(STORAGE_MODE_PRIVATE)
  
#if TARGET_OS_IOS
  // Nop since MTLStorageModeManaged is the default for iOS
#else
  textureDescriptor.storageMode = MTLStorageModePrivate;
#endif // TARGET_OS_IOS
  
#endif // STORAGE_MODE_PRIVATE
}

static inline
void validate_storage_mode(id<MTLTexture> texture)
{
#if defined(STORAGE_MODE_PRIVATE)
  
#if TARGET_OS_IOS
  // Nop
#else
# if defined(DEBUG)
  assert(texture.storageMode == MTLStorageModePrivate);
# endif // DEBUG
#endif // TARGET_OS_IOS
  
#endif // STORAGE_MODE_PRIVATE
}

// Private API

@interface GPUVMTKView ()

@property (nonatomic, retain) MetalBT709Decoder *metalBT709Decoder;

@property (nonatomic, retain) MetalScaleRenderContext *metalScaleRenderContext;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

// When a frame is decoded, the time that this frame should be displayed
// is defined in terms of the vsync frame time.

@property (nonatomic, assign) CFTimeInterval presentationTime;

@property (nonatomic, retain) GPUVDisplayLink *displayLink;

@end

@implementation GPUVMTKView
{
  unsigned int viewportWidth;
  unsigned int viewportHeight;
  
  // If set to 1, then instead of async sending to the GPU,
  // the render logic will wait for the GPU render to be completed
  // so that results of the render can be captured. This has performance
  // implications so it should only be enabled when debuging.
  int isCaptureRenderedTextureEnabled;
  
  // BT.709 render operation must write to an intermediate texture
  // (because mixing non-linear BT.709 input is not legit)
  // that can then be sampled to resize render into the view.
  id<MTLTexture> _resizeTexture;
  
  // non-zero when writing to a sRGB texture is possible, certain versions
  // of MacOSX do not support sRGB texture write operations.
  int hasWriteSRGBTextureSupport;
}

// FIXME: if view is deallocated while rendering then the render operation
// will need to finish before the view can be deallocated. Need to hold
// an active ref for long enough for a pending render operaiton to finish
// and then the view can be deallocated!

- (void) dealloc
{
  [self.displayLink cancelDisplayLink];
  
  self.displayLink = nil;
  
  MetalBT709Decoder *metalBT709Decoder = self.metalBT709Decoder;
  
  self.prevFrame = nil;
  self.currentFrame = nil;
  _resizeTexture = nil;

  if (metalBT709Decoder) {
    [metalBT709Decoder flushTextureCache];
    metalBT709Decoder = nil;
  }

  self.metalBT709Decoder = nil;
  self.metalScaleRenderContext = nil;
  
  return;
}

- (NSString*) description
{
  int width = (int) -1;
  int height = (int) -1;
  
  return [NSString stringWithFormat:@"GPUVMTKView %p %dx%d",
          self,
          width,
          height];
}

- (BOOL) configure
{
  return [self configureMetalKitView];
}

// Invoked when viewport dimensions change

- (void) layoutSubviews
{
#if TARGET_OS_IOS
  [super layoutSubviews];
#endif // TARGET_OS_IOS
  
  CGSize size = self.bounds.size;

  CGFloat scaledWidth = size.width * self.layer.contentsScale;
  CGFloat scaledHeight = size.height * self.layer.contentsScale;
  
  viewportWidth = (unsigned int) scaledWidth;
  viewportHeight = (unsigned int) scaledHeight;
  
  NSLog(@"layoutSubviews %d x %d -> viewport %d x %d", (int)size.width, (int)size.height, viewportWidth, viewportHeight);
  
  // If media is attached and the size changes from an exact match to a different size
  // that would require a scale operation then be sure that an intermediate buffer is
  // allocated. This would make it possible to not allocate an intermediate buffer
  // unless it was actually needed to implement scaling. Note that since layoutSubviews
  // can be invoked multiple times on startup, this logic might be better served in
  // a pre-play set of checks when the video is starting up but before the timer in running.
  
  return;
}

+ (void) setupViewPixelFormat:(nonnull MTKView *)mtkView
{
  // Pixels written into view are BGRA with sRGB encoding and 8 bits
  
  mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
}

- (void) setupViewOpaqueProperty:(nonnull MTKView *)mtkView
{
  BOOL isOpaqueFlag;
  
  if (self.metalBT709Decoder.hasAlphaChannel) {
    isOpaqueFlag = FALSE;
  } else {
    isOpaqueFlag = TRUE;
  }
  
#if TARGET_OS_IOS
  mtkView.opaque = isOpaqueFlag;
#else
  // MacOSX
  mtkView.layer.opaque = isOpaqueFlag;
#endif // TARGET_OS_IOS
}

- (void) setupBT709Decoder:(nonnull MTKView *)mtkView
{
  // Init Metal context, this object contains refs to metal objects
  // and util functions.
  
  id<MTLDevice> device = mtkView.device;
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  mrc.device = device;
  mrc.defaultLibrary = [device newDefaultLibrary];
  mrc.commandQueue = [device newCommandQueue];
  
  // Init metalBT709Decoder with MetalRenderContext set as a property
  
  self.metalBT709Decoder = [[MetalBT709Decoder alloc] init];
  
  self.metalBT709Decoder.metalRenderContext = mrc;
  
#if TARGET_OS_IOS
  // sRGB texture
  self.metalBT709Decoder.colorPixelFormat = mtkView.colorPixelFormat;
#else
  if (hasWriteSRGBTextureSupport) {
    self.metalBT709Decoder.colorPixelFormat = mtkView.colorPixelFormat;
  } else {
    self.metalBT709Decoder.colorPixelFormat = MTLPixelFormatRGBA16Float;
  }
#endif // TARGET_OS_IOS
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (BOOL) configureMetalKitView
{
  GPUVMTKView *mtkView = self;
  
  [self checkSRGBPixelSupport];
  
  [mtkView mtkView:mtkView drawableSizeWillChange:mtkView.drawableSize];
  
  __weak typeof(self) weakSelf = self;
  mtkView.delegate = weakSelf;
  
  {
    isCaptureRenderedTextureEnabled = 0;
    
    if (isCaptureRenderedTextureEnabled) {
      mtkView.framebufferOnly = FALSE;
    } else {
      // framebufferOnly should be TRUE, this
      // optimization means the GPU will not
      // have to write rescaled pixels back
      // to main memory.

      mtkView.framebufferOnly = TRUE;
    }
    
    // Configure internal display timer so that it is not active.
    // An explicit call to draw will be needed to kick off GPU rendering
    // on the display linked interval.
    
    mtkView.enableSetNeedsDisplay = FALSE;
    mtkView.paused = TRUE;
    
    mtkView.depthStencilPixelFormat = MTLPixelFormatInvalid;
    
    [self.class setupViewPixelFormat:mtkView];
    
    [self setupBT709Decoder:mtkView];
    
    // Decode H.264 to CoreVideo pixel buffer
    
#if defined(LOAD_ALPHA_VIDEO)
    if (self.frameSource == nil) {
      self.frameSource = [[GPUVFrameSourceAlphaVideo alloc] init];
    }
#else
    if (self.frameSource == nil) {
      self.frameSource = [[GPUVFrameSourceVideo alloc] init];
    }
#endif // LOAD_ALPHA_VIDEO
    
#if defined(LOAD_ALPHA_VIDEO)
    __weak GPUVFrameSourceAlphaVideo *weakFrameSourceVideo = (GPUVFrameSourceAlphaVideo *) self.frameSource;
#else
    __weak GPUVFrameSourceVideo *weakFrameSourceVideo = (GPUVFrameSourceVideo *) self.frameSource;
#endif // LOAD_ALPHA_VIDEO
    
    // Note that framerate and dimensions must be loaded from video metadata before
    // display link and internal resize texture can be allocated.
    
    weakFrameSourceVideo.loadedBlock = ^(BOOL success){
      NSLog(@"frameSourceVideo loadedBlock");
      
      if (!success) {
        NSLog(@"loadedBlock FAILED");
        return;
      }
      
      // Allocate scaling texture
      
      int width = weakFrameSourceVideo.width;
      int height = weakFrameSourceVideo.height;
      
      [weakSelf makeInternalMetalTexture:CGSizeMake(width, height)];
      
      float FPS = weakFrameSourceVideo.FPS;
      float frameDuration = weakFrameSourceVideo.frameDuration;

      weakSelf.FPS = FPS;
      weakSelf.frameDuration = frameDuration;
      
      NSAssert(weakSelf.displayLink, @"displayLink is nil");
      weakSelf.displayLink.FPS = FPS;
      weakSelf.displayLink.frameDuration = frameDuration;
      
      if ([weakSelf.displayLink isDisplayLinkNotInitialized]) {
        [weakSelf.displayLink makeDisplayLink];
        [weakSelf.displayLink startDisplayLink];
      }

      const float rate = 1.0f;
      
      [weakFrameSourceVideo playWithPreroll:rate block:^{
        NSLog(@"frameSourceVideo playWithPreroll block");
        
        NSAssert(weakSelf.displayLink, @"displayLink is nil");
        
        [weakSelf.displayLink checkReadyToPlay];
      }];
    };
    
    // Setup DisplayLink and associate block that will be
    // invoked once display link is running and then
    // preroll async callback has been invoked.
    
    self.displayLink = [[GPUVDisplayLink alloc] init];

    self.displayLink.loadedBlock = ^(CFTimeInterval hostTime){
      NSLog(@"GPUVDisplayLink loadedBlock");
      
      // This block is invoked when display link is running and
      // playback is ready to begin. This loaded block should
      // kick off playback, it will only be invoked once.
      
#if defined(LOAD_ALPHA_VIDEO)
      GPUVFrameSourceAlphaVideo *frameSourceVideo = (GPUVFrameSourceAlphaVideo *) weakSelf.frameSource;
#else
      GPUVFrameSourceVideo *frameSourceVideo = (GPUVFrameSourceVideo *) weakSelf.frameSource;
#endif // LOAD_ALPHA_VIDEO
      
      // FIXME: playback rate?
      
      const float rate = 1.0;
      const float frameDuration = weakSelf.frameDuration;
      
      [frameSourceVideo syncStart:rate itemTime:frameDuration atHostTime:hostTime];
    };

    // Invocation block for each display timer tick
    
    self.displayLink.invocationBlock = ^(CFTimeInterval hostTime, CFTimeInterval displayTime){
      NSLog(@"GPUVDisplayLink invocationBlock");
      
      [weakSelf displayLinkCallback:hostTime displayTime:displayTime];
    };
    
#if defined(LOAD_ALPHA_VIDEO)
    // RGB + A channels as 2 streams
    [weakFrameSourceVideo loadFromAssets:@"CarSpin.m4v" alphaResFilename:@"CarSpin_alpha.m4v"];
    //[weakFrameSourceVideo loadFromAssets:@"CountToTenA.m4v" alphaResFilename:@"CountToTenA_alpha.m4v"];    
#else
    [weakFrameSourceVideo loadFromAsset:@"CarSpin.m4v"];
    //[weakFrameSourceVideo loadFromAsset:@"BigBuckBunny640x360.m4v"];
    //[weakFrameSourceVideo loadFromAsset:@"BT709tagged.mp4"];
    //[weakFrameSourceVideo loadFromAsset:@"CountToTen.m4v"];
    
    weakFrameSourceVideo.playedToEndBlock = nil;
    weakFrameSourceVideo.finalFrameBlock = nil;
    
    weakFrameSourceVideo.uid = @"rgb";
    
    weakFrameSourceVideo.finalFrameBlock = ^{
      //NSLog(@"GPUVFrameSourceVideo.finalFrameBlock %.3f", CACurrentMediaTime());
      [weakFrameSourceVideo restart];
    };
#endif // LOAD_ALPHA_VIDEO
    
    //self.metalBT709Decoder.useComputeRenderer = TRUE;
    
    // Process 32BPP input, a CoreVideo pixel buffer is modified so that
    // an additional channel for Y is retained.
#if defined(LOAD_ALPHA_VIDEO)
    self.metalBT709Decoder.hasAlphaChannel = TRUE;
#else
    self.metalBT709Decoder.hasAlphaChannel = FALSE;
#endif // LOAD_ALPHA_VIDEO
    
    [self setupViewOpaqueProperty:mtkView];
    
    MetalBT709Gamma decodeGamma = MetalBT709GammaApple;
    
    if ((1)) {
      // Explicitly set gamma to sRGB
      decodeGamma = MetalBT709GammaSRGB;
    } else if ((0)) {
      decodeGamma = MetalBT709GammaLinear;
    }
    
    self.metalBT709Decoder.gamma = decodeGamma;
    
    // Based on BPP and gamma config, choose Metal shader and
    // configure pipelines.
    
    BOOL worked = [self.metalBT709Decoder setupMetal];
    worked = worked;
    NSAssert(worked, @"worked");
    
    // Scale render is used to blit and rescale from the 709
    // BGRA pixels into the MTKView. Note that in the special
    // case where no rescale operation is needed then the 709
    // decoder will render directly into the view.
    
    MetalScaleRenderContext *metalScaleRenderContext = [[MetalScaleRenderContext alloc] init];
    
    [metalScaleRenderContext setupRenderPipelines:self.metalBT709Decoder.metalRenderContext mtkView:mtkView];
    
    self.metalScaleRenderContext = metalScaleRenderContext;
  }
  
  return TRUE;
}

- (void)drawRect:(CGRect)rect
{
  // FIXME: need to support draw with no frame tey, since the view can be
  // rendered before decoding for video has started.
  
  // FIXME: If there is no frame object available then clear the display.
  
//  if (self.frameObj != nil) {
//    [self displayFrame];
//  } else {
//    glClearColor(0.0, 0.0, 0.0, 1.0);
//    glClear(GL_COLOR_BUFFER_BIT);
//  }

  [self displayFrame];
}

// Called when a video frame becomes available, while the video framerate may
// change the video frame on each step of frame duration length, it is also
// possible that one given frame could continue to display for multiple frames.

- (void)displayFrame
{
  BOOL worked;
  
  int renderWidth = viewportWidth;
  int renderHeight = viewportHeight;
  
  if (viewportWidth == 0) {
    NSLog(@"view dimensions not configured during displayFrame");
    return;
  }
  
  if (_resizeTexture == nil) {
    NSLog(@"_resizeTexture not allocated in displayFrame");
    return;
  }
  
  // Metal has been initialized at this point and the CAMetalLayer
  // used internally by MTKView has been allocated and configured.
  // Verify that the framebufferOnly optimization is enabled.
  
#if defined(DEBUG)
  {
    CAMetalLayer *metalLayer = (CAMetalLayer *) self.layer;
    assert(metalLayer.framebufferOnly == TRUE);
  }
#endif // DEBUG
  
  // Flush texture to release Metal/CoreVideo textures and pixel buffers.
  // Note that this is executed before checking nil conditions so that
  // a flush will still be done even if playback is stopping.
  
  MetalBT709Decoder *metalBT709Decoder = self.metalBT709Decoder;
  MetalRenderContext *mrc = metalBT709Decoder.metalRenderContext;
  
  [metalBT709Decoder flushTextureCache];
  
  // If player is not actually playing yet then nothing is ready
  
//  if (self.player.currentItem == nil) {
//    NSLog(@"player not playing yet in drawInMTKView");
//    return;
//  }
  
  if (self.currentFrame == nil) {
    NSLog(@"currentFrame is nil in displayFrame");
    return;
  }
  
  // Input to sRGB texture render comes from H.264 source
  
  CVPixelBufferRef rgbPixelBuffer = NULL;
  CVPixelBufferRef alphaPixelBuffer = NULL;
  
  // Get most recently extracted frame from the video output source
  
  // FIXME: add "ready" flag to determine if pixel buffer data is valid?
  
#if defined(DEBUG)
  assert(self.currentFrame != nil);
#endif // DEBUG
  
  rgbPixelBuffer = self.currentFrame.yCbCrPixelBuffer;
  
#if defined(DEBUG)
  assert(rgbPixelBuffer != NULL);
#endif // DEBUG
  
  if (self.currentFrame.alphaPixelBuffer != nil) {
    alphaPixelBuffer = self.currentFrame.alphaPixelBuffer;
  }
  
  // This should never happen
  
#if defined(DEBUG)
  assert(rgbPixelBuffer != NULL);
#endif // DEBUG
  
  if (rgbPixelBuffer == NULL) {
    return;
  }
  
  // Create a new command buffer for each render pass to the current drawable
  id<MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  commandBuffer.label = @"BT709 Render";
  
  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
  
  BOOL isExactlySameSize =
  (renderWidth == ((int)CVPixelBufferGetWidth(rgbPixelBuffer))) &&
  (renderHeight == ((int)CVPixelBufferGetHeight(rgbPixelBuffer))) &&
  (renderPassDescriptor != nil);
  
  if ((0)) {
    // Phony up exact match results just for testing purposes, this
    // would generate slightly wrong non-linear resample results
    // if the dimensions do not exactly match.
    isExactlySameSize = 1;
    renderWidth = (int)CVPixelBufferGetWidth(rgbPixelBuffer);
    renderHeight = (int)CVPixelBufferGetHeight(rgbPixelBuffer);
  }
  
  if (isExactlySameSize) {
    if (isCaptureRenderedTextureEnabled) {
      // Debug render into the intermediate texture when capture is
      // enabled to determine if there is any difference between
      // rendering into a texture and rendering into the view.
      
      int renderWidth = (int) _resizeTexture.width;
      int renderHeight = (int) _resizeTexture.height;
      
      [metalBT709Decoder decodeBT709:rgbPixelBuffer
                    alphaPixelBuffer:alphaPixelBuffer
                     bgraSRGBTexture:_resizeTexture
                       commandBuffer:commandBuffer
                renderPassDescriptor:nil
                         renderWidth:renderWidth
                        renderHeight:renderHeight
                  waitUntilCompleted:FALSE];
    }
    
    // Render directly into the view, this optimization reduces IO
    // and results in a significant performance improvement.
    
    worked = [metalBT709Decoder decodeBT709:rgbPixelBuffer
                           alphaPixelBuffer:alphaPixelBuffer
                            bgraSRGBTexture:nil
                              commandBuffer:commandBuffer
                       renderPassDescriptor:renderPassDescriptor
                                renderWidth:renderWidth
                               renderHeight:renderHeight
                         waitUntilCompleted:FALSE];
    
    if (worked) {
#if TARGET_OS_IOS
      CFTimeInterval minFramerate = self.frameDuration;
      [commandBuffer presentDrawable:self.currentDrawable afterMinimumDuration:minFramerate];
#else
      CFTimeInterval presentationTime = self.presentationTime;
      [commandBuffer presentDrawable:self.currentDrawable atTime:presentationTime];
//#if defined(DEBUG)
//      NSLog(@"PRESENT FRAME at host time %.3f : %.3f", presentationTime, CACurrentMediaTime());
//#endif // DEBUG
#endif // TARGET_OS_IOS
    }
  } else {
    // Viewport dimensions do not exactly match the input texture
    // dimensions, so a 2 pass render operation with an
    // intermediate texture is required.
    
    if (renderPassDescriptor != nil)
    {
      int renderWidth = (int) _resizeTexture.width;
      int renderHeight = (int) _resizeTexture.height;
      
      worked = [metalBT709Decoder decodeBT709:rgbPixelBuffer
                             alphaPixelBuffer:alphaPixelBuffer
                              bgraSRGBTexture:_resizeTexture
                                commandBuffer:commandBuffer
                         renderPassDescriptor:nil
                                  renderWidth:renderWidth
                                 renderHeight:renderHeight
                           waitUntilCompleted:FALSE];
      
#if defined(DEBUG)
      NSAssert(worked, @"decodeBT709 worked");
#endif // DEBUG
      if (!worked) {
        return;
      }
    }
    
    // Invoke scaling operation to fit the intermediate buffer
    // into the current width and height of the viewport.
    
    worked = [self.metalScaleRenderContext renderScaled:mrc
                                       mtkView:self
                                   renderWidth:renderWidth
                                  renderHeight:renderHeight
                                 commandBuffer:commandBuffer
                          renderPassDescriptor:renderPassDescriptor
                                   bgraTexture:_resizeTexture];
    
    if (worked) {
      // Present drawable and make sure it is displayed for at least
      // this long, this is important to avoid a weird case where
      // a 60 FPS display link could present a drawable faster
      // than 30 FPS (assuming the movie is 30 FPS).
      
#if TARGET_OS_IOS
      CFTimeInterval minFramerate = self.frameDuration;
      [commandBuffer presentDrawable:self.currentDrawable afterMinimumDuration:minFramerate];
#else
      CFTimeInterval presentationTime = self.presentationTime;
      [commandBuffer presentDrawable:self.currentDrawable atTime:presentationTime];
//#if defined(DEBUG)
//      NSLog(@"PRESENT FRAME at host time %.3f : %.3f", presentationTime, CACurrentMediaTime());
//#endif // DEBUG
#endif // TARGET_OS_IOS
    }
  }
  
  if (isCaptureRenderedTextureEnabled) {
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    // Wait for the GPU to finish rendering
    [commandBuffer waitUntilCompleted];
  } else {
    [commandBuffer commit];
  }
  
  // Internal resize texture can only be captured when it is sRGB texture. In the case
  // of MacOSX that makes use a linear 16 bit intermeiate texture, no means to
  // capture the intermediate form aside from another render pass that reads from
  // the intermediate and writes into a lower precision texture.
  
  if (isCaptureRenderedTextureEnabled && (_resizeTexture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB)) {
    // Capture results of intermediate render to same size texture
    
    int width = (int) _resizeTexture.width;
    int height = (int) _resizeTexture.height;
    
    int bpp = 24;
    if (self.metalBT709Decoder.hasAlphaChannel == TRUE) {
      // 32 BPP
      bpp = 32;
    }
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
    
    // Copy from texture into framebuffer as BGRA pixels
    
    [_resizeTexture getBytes:(void*)renderedFB.pixels
                 bytesPerRow:width*sizeof(uint32_t)
               bytesPerImage:width*height*sizeof(uint32_t)
                  fromRegion:MTLRegionMake2D(0, 0, width, height)
                 mipmapLevel:0
                       slice:0];
    
    if (1) {
      // texture is sRGB
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      renderedFB.colorspace = cs;
      CGColorSpaceRelease(cs);
    }
    
    NSData *pngData = [renderedFB formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:@"DUMP_internal_sRGB_texture.png"];
    BOOL worked = [pngData writeToFile:path atomically:TRUE];
    assert(worked);
    NSLog(@"wrote %@ as %d bytes", path, (int)pngData.length);
  }
  
  if (isCaptureRenderedTextureEnabled) {
    // Capture output of the resize operation as sRGB pixels
    
    id<MTLTexture> texture = renderPassDescriptor.colorAttachments[0].texture;
    
    int width = (int) texture.width;
    int height = (int) texture.height;
    
    int bpp = 24;
    if (self.metalBT709Decoder.hasAlphaChannel == TRUE) {
      // 32 BPP
      bpp = 32;
    }
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
    
    [texture getBytes:(void*)renderedFB.pixels
          bytesPerRow:width*sizeof(uint32_t)
        bytesPerImage:width*height*sizeof(uint32_t)
           fromRegion:MTLRegionMake2D(0, 0, width, height)
          mipmapLevel:0
                slice:0];
    
    if (1) {
      // Backing texture for the view is sRGB
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      renderedFB.colorspace = cs;
      CGColorSpaceRelease(cs);
    }
    
    NSData *pngData = [renderedFB formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:@"DUMP_resized_texture.png"];
    BOOL worked = [pngData writeToFile:path atomically:TRUE];
    assert(worked);
    NSLog(@"wrote %@ as %d bytes", path, (int)pngData.length);
  }
}

// This method is invoked when a new frame of video data is ready to be displayed.

- (void) nextFrameReady:(GPUVFrame*)nextFrame {
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  //@synchronized (self)
  {
#if defined(DEBUG)
    // Should drop last ref to previous GPUVFrame here
    if (self.prevFrame != nil) {
      self.prevFrame = nil;
    }
#endif // DEBUG
    self.prevFrame = self.currentFrame;
    self.currentFrame = nextFrame;
  }
}

- (void) checkSRGBPixelSupport
{
  // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
  // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0) as sRGB
  
#if TARGET_OS_IOS
  hasWriteSRGBTextureSupport = 1;
#else
  // MacOSX 10.14 or newer needed to support sRGB texture writes
  
  if (hasWriteSRGBTextureSupport == 1) {
    return;
  }
  
  NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
  
  if (version.majorVersion >= 10 && version.minorVersion >= 14) {
    // Supports sRGB texture write feature.
    hasWriteSRGBTextureSupport = 1;
  } else {
    hasWriteSRGBTextureSupport = 0;
  }
  
  // Force 16 bit float texture to be used (about 2x slower for IO bound shader)
  //hasWriteSRGBTextureSupport = 0;
#endif // TARGET_OS_IOS
}

- (BOOL) makeInternalMetalTexture:(CGSize)_resizeTextureSize
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  if (_resizeTexture != nil) {
    int updatedWidth = (int) _resizeTextureSize.width;
    int updatedHeight = (int) _resizeTextureSize.height;

    int currentWidth = (int) _resizeTexture.width;
    int currentHeight = (int) _resizeTexture.height;
    
    if (updatedWidth == currentWidth && updatedHeight == currentHeight) {
      // Same dimensions, nop
      return TRUE;
    }
  }
  
  // FIXME: this method is invoked after the video dimensions have
  // been loaded and the size of the internal texture is known.
  // In the case that the view dimensions are exactly the same
  // as the movie dimensions the internal texture is not allocated
  // in order to keep memory down for very large textures.
  
  // FIXME: do not allocate if the render size exactly matches
  // the movie size. Allocate if these do not match.
  
  assert(_resizeTextureSize.width != 0);
  assert(_resizeTextureSize.height != 0);
  assert(_resizeTexture == nil);
  
  int width = _resizeTextureSize.width;
  int height = _resizeTextureSize.height;
  
  // FIXME: pull videoSize
  
  id<MTLDevice> device = self.metalBT709Decoder.metalRenderContext.device;
  assert(device);
  
  // Init render texture that will hold resize render intermediate
  // results. This is typically sRGB, but Mac OSX may not support it.
  
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
#if TARGET_OS_IOS
  textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
#else
  // MacOSX
  if (hasWriteSRGBTextureSupport) {
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
  } else {
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
  }
#endif // TARGET_OS_IOS
  
  // Set the pixel dimensions of the texture
  textureDescriptor.width = width;
  textureDescriptor.height = height;
  
  textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
  
  // Create the texture from the device by using the descriptor,
  // note that GPU private storage mode is the default for
  // newTextureWithDescriptor, this is just here to make that clear.
  
  set_storage_mode(textureDescriptor);
  
  _resizeTexture = [device newTextureWithDescriptor:textureDescriptor];
  
  NSAssert(_resizeTexture, @"_resizeTexture");
  
  validate_storage_mode(_resizeTexture);
  
  // Debug print size of intermediate render texture
  
# if defined(DEBUG)
  {
    int numBytesPerPixel;
    
    if (hasWriteSRGBTextureSupport) {
      numBytesPerPixel = 4;
    } else {
      numBytesPerPixel = 8;
    }
    
    int numBytes = (int) (width * height * numBytesPerPixel);
    
    printf("intermediate render texture num bytes %d kB : %.2f mB\n", (int)(numBytes / 1000), numBytes / 1000000.0f);
  }
# endif // DEBUG
  
  return TRUE;
}

- (void)displayLinkCallback:(CFTimeInterval)hostTime displayTime:(CFTimeInterval)displayTime
{
#if defined(DEBUG)
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
#endif // DEBUG
  
  if ((0)) {
    NSLog(@"displayLinkCallback at system host time %.3f", CACurrentMediaTime());
    
    NSLog(@"hostTime of video %.3f", hostTime);
    NSLog(@"displayTime       %.3f", displayTime);
  }
  
  // Pull frame for time from video source
  
  id<GPUVFrameSource> frameSource = self.frameSource;
  GPUVFrame *nextFrame = [frameSource frameForHostTime:hostTime hostPresentationTime:displayTime presentationTimePtr:NULL];
  
  if (nextFrame == nil) {
    // No frame loaded for this time
  } else {
    //#if TARGET_OS_IOS
    //    // nop
    //#else
    self.presentationTime = displayTime;
    //#endif // TARGET_OS_IOS
    
    [self nextFrameReady:nextFrame];
    nextFrame = nil;
    // Draw frame directly from this timer invocation
    [self draw];
  }
  
  if ((0)) {
#if defined(LOAD_ALPHA_VIDEO)
    GPUVFrameSourceAlphaVideo *frameSourceVideo = (GPUVFrameSourceAlphaVideo *) self.frameSource;
#else
    GPUVFrameSourceVideo *frameSourceVideo = (GPUVFrameSourceVideo *) self.frameSource;
#endif // LOAD_ALPHA_VIDEO
    
    if (frameSourceVideo.loopCount > 5 && self.frameSource) {
      [self.displayLink cancelDisplayLink];
      
      [frameSourceVideo stop];
      
      self.displayLink = nil;
      self.frameSource = nil;
      frameSourceVideo = nil;
      
      [self removeFromSuperview];
    }
  }
};

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
#if TARGET_OS_IOS
  // nop
#else
  [self layoutSubviews];
#endif // TARGET_OS_IOS
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
  return;
}

// FIXME: cancel display link when view is hidden or removed from hier

@end
