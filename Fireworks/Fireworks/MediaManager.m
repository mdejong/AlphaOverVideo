//
//  MediaManager.m
//  Fireworks
//
//  Created by Mo DeJong on 10/3/15.
//  Copyright © 2019 Mo DeJong. All rights reserved.
//

#import "MediaManager.h"

#import "AutoTimer.h"

@interface MediaManager ()

@end

@implementation MediaManager

+ (MediaManager*) mediaManager
{
  return [[MediaManager alloc] init];
}

// Return RGB + Alpha asset URL pair

- (NSArray<NSURL*>*) rgbaAssetPair:(NSString*)rgb alpha:(NSString*)alpha
{
  NSURL *urlRGB = [AOVPlayer urlFromAsset:rgb];
  NSURL *urlALPHA = [AOVPlayer urlFromAsset:alpha];
  NSAssert(urlRGB != nil, @"RGB URL asset not found \"%@\"", rgb);
  NSAssert(urlALPHA != nil, @"ALPHA URL asset not found \"%@\"", alpha);
  return @[urlRGB, urlALPHA];
}

- (void) makeURLs
{
  NSString *rgbResourceName;
  NSString *alphaResourceName;

  // RGB videos
  
  self.wheelURL = [AOVPlayer urlFromAsset:@"Wheel.m4v"];
  self.redURL = [AOVPlayer urlFromAsset:@"Red.m4v"];

  // RGBA videos
  
  {
    // L12 : single firework
    rgbResourceName = @"1_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"1_2_alpha_CRF_30_24BPP.m4v";
    self.L12URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }
  
  {
    // L22 :
    rgbResourceName = @"2_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"2_2_alpha_CRF_30_24BPP.m4v";
    self.L22URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }
  
  {
    // L32 :
    rgbResourceName = @"3_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"3_2_alpha_CRF_30_24BPP.m4v";
    self.L32URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }
  
  {
    // L42 :  Two explosions, roughly at same time
    rgbResourceName = @"4_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"4_2_alpha_CRF_30_24BPP.m4v";
    self.L42URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }

  {
    // L52 :  Two explosions, roughly at same time
    rgbResourceName = @"5_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"5_2_alpha_CRF_30_24BPP.m4v";
    self.L52URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }

  {
    // L62 :
    rgbResourceName = @"6_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"6_2_alpha_CRF_30_24BPP.m4v";
    self.L62URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }

  {
    // L92 :
    rgbResourceName = @"9_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"9_2_alpha_CRF_30_24BPP.m4v";
    self.L92URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }

  {
    // L112 : large double explosion
    rgbResourceName = @"11_2_rgb_CRF_30_24BPP.m4v";
    alphaResourceName = @"11_2_alpha_CRF_30_24BPP.m4v";
    self.L112URL = [self rgbaAssetPair:rgbResourceName alpha:alphaResourceName];
  }

  return;
}


// Return array of all alpha channel fireworks media URLs.

- (NSArray*) getFireworkURLs
{
  return @[self.L12URL, self.L22URL, self.L32URL, self.L42URL, self.L52URL, self.L62URL, self.L92URL, self.L112URL];
}

@end
