/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "AOVMTKView.h"
#import "AOVPlayer.h"

#define LOAD_ALPHA_VIDEO

// Private API

@interface AAPLViewController ()

@property (nonatomic, retain) AOVPlayer *player;

@end

@implementation AAPLViewController
{
#if TARGET_OS_IOS
    IBOutlet UIImageView *imageView;
#else
    IBOutlet NSImageView *imageView;
#endif // TARGET_OS_IOS
  
    IBOutlet AOVMTKView *mtkView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
  
    // Verify that this MTKView is a AOVMTKView instance

    {
      MTKView *loadedMtkView = mtkView;
      
      if (loadedMtkView == nil)
      {
        NSLog(@"MTKView loaded from NIB is nil");
        return;
      }
      
      if ([loadedMtkView isKindOfClass:AOVMTKView.class] == FALSE) {
        NSLog(@"MTKView loaded from NIB does not extend AOVMTKView base class");
        return;
      }
    }

    BOOL alphaImageBackground = FALSE;
    // If alphaImageBackground is FALSE, background can be black or white
    BOOL blackBackground = TRUE;

#if TARGET_OS_IOS
    if (alphaImageBackground) {
        UIImage *alphaImg = [UIImage imageNamed:@"AlphaBGHalf.png"];
        assert(alphaImg);
        UIColor *patternColor = [UIColor colorWithPatternImage:alphaImg];
        imageView.backgroundColor = patternColor;
    } else {
        UIColor *color;
        if (blackBackground == FALSE) {
            color = [UIColor whiteColor];
        } else if (blackBackground) {
            color = [UIColor blackColor];
        }
        imageView.backgroundColor = color;
    }
#else
    // MacOSX
    if (alphaImageBackground) {
        NSImage *alphaImg = [NSImage imageNamed:@"AlphaBG.png"];
        assert(alphaImg);
        NSColor *patternColor = [NSColor colorWithPatternImage:alphaImg];
        [imageView setWantsLayer:YES];
        imageView.layer.backgroundColor = patternColor.CGColor;
    } else {
        NSColor *color;
        if (blackBackground == FALSE) {
            color = [NSColor whiteColor];
        } else if (blackBackground) {
            color = [NSColor blackColor];
        }
        [imageView setWantsLayer:YES];
        imageView.layer.backgroundColor = color.CGColor;
    }
#endif // TARGET_OS_IOS

    mtkView.device = MTLCreateSystemDefaultDevice();

    if(!mtkView.device)
    {
        NSLog(@"Metal is not supported on this device");
        return;
    }

    // Configure Metal view and playback logic

#if defined(LOAD_ALPHA_VIDEO)
  NSArray *clips = @[
                     //@[ [AOVPlayer urlFromAsset:@"CarSpin.m4v"], [AOVPlayer urlFromAsset:@"CarSpin_alpha.m4v"] ]
                     //@[ [AOVPlayer urlFromAsset:@"CountToTenA.m4v"], [AOVPlayer urlFromAsset:@"CountToTenA_alpha.m4v"] ]
                     @[ [AOVPlayer urlFromAsset:@"GlobeLEDAlpha.m4v"], [AOVPlayer urlFromAsset:@"GlobeLEDAlpha_alpha.m4v"] ]
                     //@[ [AOVPlayer urlFromAsset:@"Field.m4v"], [AOVPlayer urlFromAsset:@"Field_alpha.m4v"] ]
                     ];
#else
  NSArray *clips = @[
                     //[AOVPlayer urlFromAsset:@"CarSpin.m4v"]
                     [AOVPlayer urlFromAsset:@"CountToTen.m4v"]
                     ];
#endif // LOAD_ALPHA_VIDEO

    AOVPlayer *player = [AOVPlayer playerWithLoopedClips:clips];
  
    // sRGB is the default gamma setting for a AOVPlayer, but explicitly set it here
    player.decodeGamma = MetalBT709GammaSRGB;
  
    // Hold ref to AOVPlayer, note that a ref is never held by the AOVMTKView
    self.player = player;
  
    // Attach player to view, note that this is the expensive API call since
    // it will allocate textures and Metal state that depends on the player.
    BOOL worked = [mtkView attachPlayer:player];
    if(!worked)
    {
      NSLog(@"attachPlayer failed for AOVMTKView");
      return;
    }
  
    // Drop active ref to mtkView, parent window still hold a ref
    self->mtkView = nil;
}

@end
