/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "GPUVMTKView.h"

@implementation AAPLViewController
{
#if TARGET_OS_IOS
    IBOutlet UIImageView *imageView;
#else
    IBOutlet NSImageView *imageView;
#endif // TARGET_OS_IOS
  
    IBOutlet GPUVMTKView *mtkView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
  
    // Verify that this MTKView is a GPUVMTKView instance

    {
      MTKView *loadedMtkView = mtkView;
      
      if (loadedMtkView == nil)
      {
        NSLog(@"MTKView loaded from NIB is nil");
        return;
      }
      
      if ([loadedMtkView isKindOfClass:GPUVMTKView.class] == FALSE) {
        NSLog(@"MTKView loaded from NIB does not extend GPUVMTKView base class");
        return;
      }
    }

    BOOL alphaImageBackground = TRUE;
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
    BOOL worked = [mtkView configure];
    if(!worked)
    {
      NSLog(@"configure failed for GPUVMTKView");
      return;
    }
  
    // Drop active ref to mtkView, parent window still hold a ref
    self->mtkView = nil;
}

@end
