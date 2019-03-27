//
//  GPUVDisplayLink.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  This display link object generates callbacks on the main
//  thread at an interval in between the display vsync interval.

@import Foundation;
@import AVFoundation;

// GPUVDisplayLink provides

@interface GPUVDisplayLink : NSObject

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

// This block is invoked when loading conditions are completed and the display
// link is ready to drive interval updates to the invocation block.

@property (nonatomic, copy, nullable) void (^loadedBlock)(CFTimeInterval hostTime);

// This block will be invoked on the indicated interval, this block
// is invoked the second time

@property (nonatomic, copy, nullable) void (^invocationBlock)(CFTimeInterval hostTime, CFTimeInterval displayTime);

- (void) makeDisplayLink;

// Note that this method is a nop if invoked when display link is already running

- (void) startDisplayLink;

- (void) cancelDisplayLink;

// Returns TRUE if not yet initialized

- (BOOL) isDisplayLinkNotInitialized;

// This method is invoked once preroll on the video source
// has been completed. In the case where the video is ready
// to play and the display link is running then kick off
// playback in the view object. In the case where the video
// is ready to play but the display link is not running yet,
// wait until the display link is up and running.

- (void) checkReadyToPlay;

@end
