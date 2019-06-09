//
//  ViewController.m
//  Bloom
//
//  Created by Mo DeJong on 5/27/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

#import "ViewController.h"

#import "zlib.h"

#import "EPNGDecoder.h"

@import AlphaOverVideo;

@interface ViewController ()

@property (nonatomic, weak) IBOutlet AOVMTKView *mtkView;

@property (nonatomic, retain) AOVPlayer *player;

@property (nonatomic, retain) NSMutableDictionary *cachedImgeMap;

@end

@implementation ViewController

// Given an asset name, load the video data from the
// asset catalog and save into a file in the tmp dir
// so that the data can be loaded via AVFoundation APIs.

- (NSURL*) urlFromEmbeddedAsset:(NSString*)imgName
{
  NSURL *url = nil;
  
  if (self.cachedImgeMap == nil) {
    self.cachedImgeMap = [NSMutableDictionary dictionary];
  }
  NSString *tmpFilePath = self.cachedImgeMap[imgName];
  if (tmpFilePath != nil) {
    // This image data was already decoded from embedded PNG format and
    // saved to disk. Load it from disk directly to avoid having to
    // allocate memory and do IO again.
    
    url = [NSURL fileURLWithPath:tmpFilePath];
    return url;
  }
  
  // Decode asset data from PNG bytes
  
  UIImage *assetImg = [UIImage imageNamed:imgName];
  
  BOOL calcCRC = TRUE;
  int *crcPtr = NULL;
  int crcVal = 0;
  if (calcCRC) {
    crcPtr = &crcVal;
  }

  url =  [EPNGDecoder saveEmbeddedAssetToTmpDir:assetImg.CGImage
                                     pathPrefix:@"videoXXXXXX.m4v"
                                         tmpDir:nil
                                      decodeCRC:crcPtr];
  self.cachedImgeMap[imgName] = [url path];
  
  return url;
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
