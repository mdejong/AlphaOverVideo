//
//  AnimatingViewController.m
//  Fireworks
//
//  Created by Mo DeJong on 10/3/15.
//  Copyright © 2019 Mo DeJong. All rights reserved.
//

#import "AnimatingViewController.h"

#import "AppDelegate.h"

#import "AutoTimer.h"

#import "MediaManager.h"

@import AlphaOverVideo;

#include <stdlib.h>

@interface AnimatingViewController ()

@property (nonatomic, retain) id<MTLDevice> device;

@property (nonatomic, retain) IBOutlet UILabel *fireworksLabel;

@property (nonatomic, retain) AutoTimer *fireworksLabelTimer;

@property (nonatomic, retain) IBOutlet AOVMTKView *redMTKView;

@property (nonatomic, retain) AOVPlayer *redPlayer;

@property (nonatomic, retain) IBOutlet AOVMTKView *wheelMTKView;

// Seamless looping player always running in BG
@property (nonatomic, retain) AOVPlayer *wheelPlayer;

// Active players for each firework video

@property (nonatomic, retain) NSMutableArray *players;

// The field is the extents of the (X,Y,W,H) where fireworks
// can explode. The upper right corner is (0.0, 0.0) and the
// lower right corner is at (1.0, 1.0)

@property (nonatomic, retain) IBOutlet UIView *fieldContainer;

@property (nonatomic, retain) NSMutableArray *fieldSubviews;

@end

@implementation AnimatingViewController

- (void)viewDidLoad {
  [super viewDidLoad];
 
  NSAssert(self.wheelMTKView, @"wheelMTKView");
  NSAssert(self.redMTKView, @"redMTKView");
  NSAssert(self.fieldContainer, @"fieldContainer");
  NSAssert(self.fireworksLabel, @"fireworksLabel");
  
  self.fireworksLabel.hidden = TRUE;
  
  AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
  MediaManager *mediaManager = appDelegate.mediaManager;

  id<MTLDevice> device = self.device;
  if (device == nil) {
    device = MTLCreateSystemDefaultDevice();
    self.device = device;
  }
  
  [mediaManager makeURLs];
  
  NSURL *wheelURL = mediaManager.wheelURL;
  //wheelMedia.animatorRepeatCount = 0xFFFF;
  
  // Create red animation
  
  NSURL *redURL = mediaManager.redURL;

  // Red firework animated 1 time
  self.redPlayer = [AOVPlayer playerWithClip:redURL];
  // Wheel does seamless looping forever
  self.wheelPlayer = [AOVPlayer playerWithLoopedClips:@[wheelURL]];

  // Defaults to sRGB, so set BT.709 flag
  self.redPlayer.decodeGamma = AOVGammaApple;
  self.wheelPlayer.decodeGamma = AOVGammaApple;
  
  // Link player(s) to views
  
  self.redMTKView.device = device;
  self.wheelMTKView.device = device;
 
  BOOL worked;
  
  worked = [self.redMTKView attachPlayer:self.redPlayer];
  NSAssert(worked, @"attachPlayer failed");
  [self.wheelMTKView attachPlayer:self.wheelPlayer];
  NSAssert(worked, @"attachPlayer failed");
  
  return;
}

- (void) viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  
  // Kick off fireworks label animation
  
  self.fireworksLabelTimer = [AutoTimer autoTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(startAnimatingFireworkLabel)
                                                          userInfo:nil
                                                          repeats:FALSE];
  
  AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
  MediaManager *mediaManager = appDelegate.mediaManager;
  
  // FIXME: Need a way to defer actually starting videos actually preoaded and ready to play
  // as opposed to auto-start which they do now.
  
  //[self.wheelPlayer play];
  //[self.redPlayer play];
}

- (void) startAnimatingFireworkLabel
{
  self.fireworksLabel.hidden = FALSE;
  
  self.fireworksLabelTimer = [AutoTimer autoTimerWithTimeInterval:2.5
                                                           target:self
                                                         selector:@selector(stopAnimatingFireworkLabel)
                                                         userInfo:nil
                                                          repeats:FALSE];
}

- (void) stopAnimatingFireworkLabel
{
  self.fireworksLabel.hidden = TRUE;
  self.fireworksLabelTimer = nil;
 
  AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
  MediaManager *mediaManager = appDelegate.mediaManager;

  // Put away the red opaque firework view
  
  // FIXME: Stop animation and hide
  
  //[mediaManager.redMedia stopAnimator];
  //[self.redContainer removeFromSuperview];
  
  [self.redMTKView removeFromSuperview];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
  [super touchesEnded:touches withEvent:event];
  
  //NSLog(@"Touches Began");
  
  if (self.fireworksLabel.hidden == FALSE) {
    // Do not allow until label is hidden
    return;
  }
  
  [self logTouchesFor:event];
  
  CGPoint location = [self firstTouchLocation:event];
  
  // The location coordinate is in terms of the (X,Y) in self.view
  
  float normX = location.x / self.view.bounds.size.width;
  float normY = location.y / self.view.bounds.size.height;
  
  NSLog(@"(X,Y): (%d, %d)", (int)location.x, (int)location.y);
  NSLog(@"(W x H): (%d x %d)", (int)self.view.bounds.size.width, (int)self.view.bounds.size.height);
  NSLog(@"NORM (X,Y): (%f, %f)", normX, normY);
  
  // Map self.view norm coords into self.fieldContainer

  CGRect frame = self.fieldContainer.frame;
  CGRect bounds = self.fieldContainer.bounds;
  
  NSLog(@"fieldContainer.frame : (%0.2f, %0.2f) %0.2f x %0.2f", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
  NSLog(@"fieldContainer.bounds : (%0.2f, %0.2f) %0.2f x %0.2f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
  
  int fieldContainerX = frame.origin.x + (frame.size.width * normX);
  int fieldContainerY = frame.origin.y + (frame.size.height * normY);
  
  NSLog(@"fieldContainer (X,Y): (%d, %d)", fieldContainerX, fieldContainerY);
  
  // Detemine rough (0.0, 0.0) -> (1.0, 1.0) coordinates
  
  AOVMTKView *fieldSubview = [[AOVMTKView alloc] initWithFrame:bounds];

  [self.fieldContainer addSubview:fieldSubview];

  if (self.fieldSubviews == nil) {
    self.fieldSubviews = [NSMutableArray array];
  }
  [self.fieldSubviews addObject:fieldSubview];
  
  AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
  MediaManager *mediaManager = appDelegate.mediaManager;

  NSAssert(mediaManager.L42URL, @"L42URL");
  NSAssert(mediaManager.L112URL, @"L112URL");
  
//  AVAnimatorMedia *media = nil;
  
//  if (event.allTouches.count > 1) {
//    // More than 1 finger down on the touch
//    media = mediaManager.L42Media;
//  } else {
//    media = mediaManager.L112Media;
//  }
  
  // Randomly choose a firework to display
  
  NSArray *arr = [mediaManager getFireworkURLs];
  int off = (int) arc4random_uniform((u_int32_t)arr.count);
  NSArray *urlTuple = arr[off];
  
  //[self stopMediaAndRemoveView:media];
  
  AOVPlayer *player = [AOVPlayer playerWithClip:urlTuple];
  
  // Note that each player must be retained in an array, since the window
  // does not hold a ref to the player.
  
  if (self.players == nil) {
    self.players = [NSMutableArray array];
  }
  [self.players addObject:player];
  
  // Define a configuration block that is executed when the movie
  // dimensions are available. Before the movie file is parsed,
  // the width and height dimensions are not available.
  
  __weak typeof(fieldSubview) weakFieldSubview = fieldSubview;
  __weak typeof(player) weakPlayer = player;
  
  player.videoSizeReadyBlock = ^(CGSize pixelSize, CGSize pointSize){
    //int w = (int) pointSize.width;
    //int h = (int) pointSize.height;

    // Normally, one would use pointSize dimensions to get a 1 to 1
    // scaling from pixels to screen, but the original videos are
    // a little small, so scale them up to 2x size by using the
    // pixel size for the view points values.
    
    int w = (int) pixelSize.width;
    int h = (int) pixelSize.height;
    
    int hW = w / 2;
    int hH = h / 2;
    
    int originX = fieldContainerX - hW;
    int originY = fieldContainerY - hH;
    
    weakFieldSubview.frame = CGRectMake(originX, originY, w, h);
    
    NSLog(@"subview (X,Y): (%f, %f) and W x H : (%f, %f)", weakFieldSubview.frame.origin.x, weakFieldSubview.frame.origin.y, weakFieldSubview.frame.size.width, weakFieldSubview.frame.size.width);
  };
  
  // This callback block is invoked when the video is finished playing
  
  player.videoPlaybackFinishedBlock = ^{
    [self cleanupViewAfterStopping:weakFieldSubview player:weakPlayer];
  };
  
  fieldSubview.device = self.device;
  
  [fieldSubview attachPlayer:player];
  
//  [[NSNotificationCenter defaultCenter] addObserver:self
//                                           selector:@selector(animatorDoneNotification:)
//                                               name:AVAnimatorDoneNotification
//                                             object:media];
//
//  [fieldSubview attachMedia:media];
//
//  [media startAnimator];
  
  return;
}

- (void) logTouchesFor:(UIEvent*)event
{
  int count = 1;
  
  for (UITouch* touch in event.allTouches) {
    CGPoint location = [touch locationInView:self.view];
    
    NSLog(@"%d: (%.0f, %.0f)", count, location.x, location.y);
    
//    CGPoint location = [touch locationInView:self.view];
    
    count++;
  }
}

- (CGPoint) firstTouchLocation:(UIEvent*)event
{
  for (UITouch* touch in event.allTouches) {
    CGPoint location = [touch locationInView:self.view];
    return location;
  }
  return CGPointMake(0, 0);
}


- (void) cleanupViewAfterStopping:(AOVMTKView*)subview player:(AOVPlayer*)player
{
  // Query player, then detach, then remove from superview and deallocate
  [subview detachPlayer:player];
  [subview removeFromSuperview];
  
  [self.fieldSubviews removeObject:subview];
  [self.players removeObject:player];
}

@end
