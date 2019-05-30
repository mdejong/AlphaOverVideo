//
//  ViewController.m
//  Bloom
//
//  Created by Mo DeJong on 5/27/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

#import "ViewController.h"

#import "zlib.h"

@import AlphaOverVideo;

@interface ViewController ()

@property (nonatomic, weak) IBOutlet AOVMTKView *mtkView;

@property (nonatomic, retain) AOVPlayer *player;

@end

@implementation ViewController

// Return unique file path in temp dir

- (NSString*) getUniqueTmpDirPath
{
  NSString *tmpDir = NSTemporaryDirectory();
  const char *rep = [[tmpDir stringByAppendingPathComponent:@"videoXXXXXX.m4v"] fileSystemRepresentation];
  char *temp_template = strdup(rep);
  int largeFD = mkstemp(temp_template);
  NSString *largeFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:temp_template length:strlen(temp_template)];
  free(temp_template);
  NSAssert(largeFD != -1, @"largeFD");
  NSAssert(largeFileName, @"largeFileName");
  return largeFileName;
}

// Given image data that contains grayscale bytes, save these
// literal bytes into a file and return a NSURL* for this
// file stored in the tmp directory.

- (NSURL*) saveEmbeddedAssetToTmpDir:(CGImageRef)cgImage
{
  int bitmapWidth = (int) CGImageGetWidth(cgImage);
  int bitmapHeight = (int) CGImageGetHeight(cgImage);
  int bitmapLength = bitmapWidth * bitmapHeight;
  
  CGRect imageRect = CGRectMake(0, 0, bitmapWidth, bitmapHeight);
  
  // Grayscale color space
  //CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
  
  // Create bitmap content with current image size and grayscale colorspace
  CGContextRef context = CGBitmapContextCreate(nil, bitmapWidth, bitmapHeight, 8, bitmapWidth, colorSpace, kCGImageAlphaNone);
  
  // Draw image into current context, with specified rectangle
  // using previously defined context (with grayscale colorspace)
  CGContextDrawImage(context, imageRect, cgImage);
  
  uint8_t *contextPtr = (uint8_t *) CGBitmapContextGetData(context);
  assert(contextPtr != NULL);
  
  assert(CGBitmapContextGetBytesPerRow(context) == bitmapWidth);
  
  // Walk backwards from the end of the buffer until a non-zero value is found.
  
  uint8_t *endPtr = contextPtr + bitmapLength - 1;
  
  while ((endPtr != contextPtr) && (*endPtr == 0)) {
    endPtr--;
  }
  
  int bufferLength = (int) (endPtr - contextPtr + 1);
  
  NSData *rawBytes = [NSData dataWithBytes:contextPtr length:bufferLength];
  
  if ((0)) {
  for (int i = 0; i < rawBytes.length; i++) {
    printf("bufffer[%d] = 0x%02X\n", i, ((uint8_t*)rawBytes.bytes)[i]);
  }
  }
  
  // Signature of decoded PNG data
  
  if ((0)) {    
    uint32_t crc = (uint32_t) crc32(0, (void*)rawBytes.bytes, (int)rawBytes.length);
    
    printf("crc 0x%08X based on %d input buffer bytes\n", crc, (int)rawBytes.length);
  }

  // FIXME: optimize by creating NSData with no copy flag, then write,
  // then release bitmap context
  
  // Release colorspace, context and bitmap information
  CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  
  NSString *tmpPath = [self getUniqueTmpDirPath];
  
  BOOL worked = [rawBytes writeToFile:tmpPath atomically:TRUE];
  
  if (worked == FALSE) {
    return nil;
  }
  
  NSURL *url = [NSURL fileURLWithPath:tmpPath];
  return url;
}

// Given an asset name, load the video data from the
// asset catalog and save into a file in the tmp dir
// so that the data can be loaded via AVFoundation APIs.

- (NSURL*) urlFromEmbeddedAsset:(NSString*)imgName
{
  // Decode asset data from PNG bytes
  
  UIImage *assetImg = [UIImage imageNamed:imgName];
  
  return [self saveEmbeddedAssetToTmpDir:assetImg.CGImage];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view.
  
  NSAssert(self.mtkView, @"mtkView");
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  if (device == nil)
  {
    NSLog(@"Metal is not supported on this device");
    return;
  }
  
  self.mtkView.device = device;

  // Load from sliced asset, note that the specific device will load
  // the video of the proper size for that device, either iPhone
  // @2x or @3x, any iPad device load the same full screen video.
  
  NSURL *url1 = [self urlFromEmbeddedAsset:@"BloomVideo"];
  
  AOVPlayer *player = [AOVPlayer playerWithLoopedClip:url1];
  
  self.player = player;
  
  // Explicitly indicate that video is encoded with Apple BT.709 gamma
  player.decodeGamma = AOVGammaApple;
  
  BOOL worked = [self.mtkView attachPlayer:player];

  if (!worked)
  {
    NSLog(@"attach failed for AOVMTKView");
    return;
  }
}

@end
