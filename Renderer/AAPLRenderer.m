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
#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"
#import "MetalBT709Decoder.h"
#import "MetalScaleRenderContext.h"
#import "BGRAToBT709Converter.h"
#import "BGDecodeEncode.h"
#import "CGFrameBuffer.h"
#import "CVPixelBufferUtils.h"

static void *AVPlayerItemStatusContext = &AVPlayerItemStatusContext;

@interface AAPLRenderer ()

@property (nonatomic, retain) MetalBT709Decoder *metalBT709Decoder;

@property (nonatomic, retain) MetalScaleRenderContext *metalScaleRenderContext;

// Player instance objects to decode CoreVideo buffers from an asset item

@property (nonatomic, retain) AVPlayer *player;
@property (nonatomic, retain) AVPlayerItem *playerItem;
@property (nonatomic, retain) AVPlayerItemVideoOutput *playerItemVideoOutput;
@property (nonatomic, retain) dispatch_queue_t playerQueue;

@property (nonatomic, copy) NSArray *frames;
@property (nonatomic, copy) NSArray *alphaFrames;

@property (nonatomic, assign) int frameNum;

@property (nonatomic, assign) int skipCount;

@end

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


// Main class performing the rendering
@implementation AAPLRenderer
{
  // If set to 1, then instead of async sending to the GPU,
  // the render logic will wait for the GPU render to be completed
  // so that results of the render can be captured. This has performance
  // implications so it should only be enabled when debuging.
  int isCaptureRenderedTextureEnabled;
  
  // Input to sRGB texture render comes from H.264 source
  CVPixelBufferRef _yCbCrPixelBuffer;
  
  // Secondary Alpha channel texture input
  CVPixelBufferRef _alphaPixelBuffer;
  
  // BT.709 render operation must write to an intermediate texture
  // (because mixing non-linear BT.709 input is not legit)
  // that can then be sampled to resize render into the view.
  id<MTLTexture> _resizeTexture;
  
  // The current size of our view so we can use this in our render pipeline
  vector_uint2 _viewportSize;
  
  // non-zero when writing to a sRGB texture is possible, certain versions
  // of MacOSX do not support sRGB texture write operations.
  int hasWriteSRGBTextureSupport;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
  self = [super init];
  if(self)
  {
    isCaptureRenderedTextureEnabled = 0;
    
    id<MTLDevice> device = mtkView.device;
    
    if (isCaptureRenderedTextureEnabled) {
      mtkView.framebufferOnly = false;
    }

    //mtkView.preferredFramesPerSecond = 60;
    //mtkView.preferredFramesPerSecond = 30;
    //mtkView.preferredFramesPerSecond = 20;
    mtkView.preferredFramesPerSecond = 10;
    
    // Init Metal context, this object contains refs to metal objects
    // and util functions.
    
    MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
    
    mrc.device = device;
    mrc.defaultLibrary = [device newDefaultLibrary];
    mrc.commandQueue = [device newCommandQueue];
    
    // Decode H.264 to CoreVideo pixel buffer
    
    [self decodeCarSpinAlphaLoop];
    //CVPixelBufferRetain(_yCbCrPixelBuffer);
    
    //int width = (int) CVPixelBufferGetWidth(_yCbCrPixelBuffer);
    //int height = (int) CVPixelBufferGetHeight(_yCbCrPixelBuffer);
    
    int width = 960;
    int height = 720;
    
    // Configure Metal view so that it treats pixels as sRGB values.
    
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    
    {
      // Init render texture that will hold resize render intermediate
      // results. This is typically sRGB, but Mac OSX may not support it.
      
      MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
      
      textureDescriptor.textureType = MTLTextureType2D;
      
      // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
      // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0) as sRGB

#if TARGET_OS_IOS
      hasWriteSRGBTextureSupport = 1;
#else
      // MacOSX 10.14 or newer needed to support sRGB texture writes
      
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
    }
    
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
    
    //self.metalBT709Decoder.useComputeRenderer = TRUE;

    // Process 32BPP input, a CoreVideo pixel buffer is modified so that
    // an additional channel for Y is retained.
    self.metalBT709Decoder.hasAlphaChannel = FALSE;
    
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
    
    MetalBT709Gamma decodeGamma = MetalBT709GammaApple;
    
    if ((1)) {
      // Explicitly set gamma to sRGB
      decodeGamma = MetalBT709GammaSRGB;
    } else if ((0)) {
      decodeGamma = MetalBT709GammaLinear;
    }

    self.metalBT709Decoder.gamma = decodeGamma;
    
    BOOL worked = [self.metalBT709Decoder setupMetal];
    worked = worked;
    NSAssert(worked, @"worked");
    
    // Scale render is used to blit and rescale from the 709
    // BGRA pixels into the MTKView. Note that in the special
    // case where no rescale operation is needed then the 709
    // decoder will render directly into the view.
    
    MetalScaleRenderContext *metalScaleRenderContext = [[MetalScaleRenderContext alloc] init];
    
    [metalScaleRenderContext setupRenderPipelines:mrc mtkView:mtkView];
    
    self.metalScaleRenderContext = metalScaleRenderContext;
  }
  
  return self;
}

- (void) decodeCarSpinAlphaLoop
{
  NSString *resFilename = @"CarSpin.m4v";
  
  int width = 960;
  int height = 720;
  
  self.player = [[AVPlayer alloc] init];
  
  NSString *path = [[NSBundle mainBundle] pathForResource:resFilename ofType:nil];
  NSAssert(path, @"path is nil");
  
  NSURL *assetURL = [NSURL fileURLWithPath:path];

  self.playerItem = [AVPlayerItem playerItemWithURL:assetURL];
  
  NSLog(@"PlayerItem URL %@", assetURL);
  
  NSDictionary *pixelBufferAttributes = [BGRAToBT709Converter getPixelBufferAttributes];
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionaryWithDictionary:pixelBufferAttributes];
  
  // Add kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
  
  mDict[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  
  pixelBufferAttributes = [NSDictionary dictionaryWithDictionary:mDict];
  
  self.playerItemVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];;
  
  // FIXME: does this help ?
  self.playerItemVideoOutput.suppressesPlayerRendering = TRUE;
  
  self.playerQueue = dispatch_queue_create("com.decode.carspin_rgb", DISPATCH_QUEUE_SERIAL);
  
  __weak AAPLRenderer* weakSelf = self;
  
  [self.playerItemVideoOutput setDelegate:weakSelf queue:self.playerQueue];
  
  //self.frames = cvPixelBuffers;
  self.frameNum = 0;
  //self.skipCount = 30;
  
  // @"CarSpin_alpha.m4v"
  
  // Grab just the first texture, return retained ref
  
  //CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  //CVPixelBufferRetain(cvPixelBuffer);
  
  float ONE_FRAME_DURATION = 1.0f / 10.0f;
  
  // Async logic to parse M4V headers to get tracks and other metadata
  
  AVAsset *asset = [self.playerItem asset];
  
  NSArray *assetKeys = @[@"duration", @"playable", @"tracks"];
  
  [asset loadValuesAsynchronouslyForKeys:assetKeys completionHandler:^{
    
    if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
      NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
      if ([tracks count] > 0) {
        // Choose the first video track. Ignore other tracks if found
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        
//        [weakSelf.playerItem addOutput:weakSelf.playerItemVideoOutput];
        
        dispatch_async(dispatch_get_main_queue(), ^{
                      [weakSelf.playerItem addOutput:weakSelf.playerItemVideoOutput];
                      [weakSelf.player replaceCurrentItemWithPlayerItem:weakSelf.playerItem];
                      [weakSelf.playerItem seekToTime:kCMTimeZero completionHandler:nil];
                      [weakSelf.playerItemVideoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:ONE_FRAME_DURATION];
                      [weakSelf.player play];
                    });
      }
    }
    
  }];
  
  return;
}

- (CVPixelBufferRef) decodeCarSpinAlphaLoopSingleFrame
{
  NSString *resFilename = @"CarSpin.m4v";
  
  int width = 960;
  int height = 720;
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(width, height)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  self.frames = cvPixelBuffers;
  self.frameNum = 0;
  self.skipCount = 30;
  
  if ((1)) {
    NSString *resFilename = @"CarSpinAF10_alpha.m4v";
    
    NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                      frameDuration:1.0/30
                                                                         renderSize:CGSizeMake(width, height)
                                                                         aveBitrate:0];
    NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
    
    self.alphaFrames = cvPixelBuffers;
  }
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
  BOOL worked;
  
//  if (self.frameNum >= self.frames.count) {
//    self.frameNum = 0;
//  }
  
  // If player is not actually playing yet then nothing is ready
  
  if (self.player.currentItem == nil) {
    NSLog(@"player not playing yet on display frame %d", (int)self.frameNum + 1);
    return;
  }
  
  // Input to sRGB texture render comes from H.264 source
  CVPixelBufferRef rgbPixelBuffer = NULL;
  CVPixelBufferRef alphaPixelBuffer = NULL;
  
  int currentFrameNum = self.frameNum;
  
  //NSLog(@"display frame %d", (int)self.frameNum + 1);
  
  // Check for next frame at time t = (frameNum * duration)
  
  CFTimeInterval outputItemTime;
  outputItemTime = currentFrameNum * (1.0f / 10); // 10 FPS
  
  CMTime syncTime = CMTimeMake(round(outputItemTime * 1000.0f), 1000);

  NSLog(@"display frame %d : at vsync time %0.2f : %d / %d", (int)self.frameNum + 1, outputItemTime, (int)syncTime.value, (int)syncTime.timescale);
  
  AVPlayerItemVideoOutput *playerItemVideoOutput = self.playerItemVideoOutput;
  
  if ([playerItemVideoOutput hasNewPixelBufferForItemTime:syncTime]) {
    rgbPixelBuffer = [playerItemVideoOutput copyPixelBufferForItemTime:syncTime itemTimeForDisplay:NULL];
  }
  
  self.frameNum += 1;
  
  if (rgbPixelBuffer == NULL) {
    // FIXME: When no frame to display, what the do then?
    NSLog(@"hasNewPixelBufferForItemTime is false at vsync time %0.2f", outputItemTime);
    return;
  }
  
//  if (self.alphaFrames != nil) {
//    alphaPixelBuffer = (__bridge CVPixelBufferRef) self.alphaFrames[currentFrameNum];
//  }
  
//  if (self.skipCount == 0) {
//    self.skipCount = 30;
//    self.frameNum += 1;
//  }
//  self.skipCount -= 1;
  
  assert(rgbPixelBuffer != NULL);
  if (self.alphaFrames != nil) {
    assert(alphaPixelBuffer != NULL);
  }

  MetalBT709Decoder *metalBT709Decoder = self.metalBT709Decoder;
  MetalRenderContext *mrc = metalBT709Decoder.metalRenderContext;
  
  // Create a new command buffer for each render pass to the current drawable
  id<MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  commandBuffer.label = @"BT709 Render";
  
  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
  
  int renderWidth = (int) _viewportSize.x;
  int renderHeight = (int) _viewportSize.y;
  
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
      // Schedule a present once the framebuffer is complete using the current drawable
      [commandBuffer presentDrawable:view.currentDrawable];
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
    
    [self.metalScaleRenderContext renderScaled:mrc
                                       mtkView:view
                                   renderWidth:renderWidth
                                  renderHeight:renderHeight
                                 commandBuffer:commandBuffer
                          renderPassDescriptor:renderPassDescriptor
                                   bgraTexture:_resizeTexture];
  }
  
  if (isCaptureRenderedTextureEnabled) {
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    // Wait for the GPU to finish rendering
    [commandBuffer waitUntilCompleted];
  } else {
    [commandBuffer commit];
  }
  
  // FIXME: frame of RGB + Alpha should be retained until next frame is ready
  
  _yCbCrPixelBuffer = rgbPixelBuffer;
  
  CVPixelBufferRelease(rgbPixelBuffer);
  if (alphaPixelBuffer) {
    CVPixelBufferRelease(alphaPixelBuffer);
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

#pragma mark - AVPlayerItemOutputPullDelegate

- (void)outputMediaDataWillChange:(AVPlayerItemOutput*)sender
{
  // Restart display link.
  //[[self displayLink] setPaused:NO];
  
  NSLog(@"outputMediaDataWillChange");
  
  return;
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
        //self.playerView.presentationRect = [[_player currentItem] presentationSize];
        CGSize playSize = [[self.player currentItem] presentationSize];
        NSLog(@"AVPlayer viewport dimensions : %d x %d", (int)playSize.width, (int)playSize.height);
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
