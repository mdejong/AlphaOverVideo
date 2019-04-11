//
//  AOVFrameSource.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  This frame source protocol defines a generic interface
//  that can be implemented by any class in order to generate
//  AOVFrame objects that can be consumed by a AOVMTKView.

@import Foundation;
@import AVFoundation;

#import "AOVFrame.h"

// AOVFrameSource protocol

@protocol AOVFrameSource

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

@property (nonatomic, readonly) int loopCount;
@property (nonatomic, assign) int loopMaxCount;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// Given a host time offset, return a AOVVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.
// The hostPresentationTime indicates the host time when the
// decoded frame would be displayed.
// The presentationTimePtr pointer provides a way to query the
// DTS (display time stamp) of the decoded frame in the H.264 stream.
// Note that presentationTimePtr can be NULL.

- (AOVFrame*) frameForHostTime:(CFTimeInterval)hostTime
           hostPresentationTime:(CFTimeInterval)hostPresentationTime
            presentationTimePtr:(float*)presentationTimePtr;

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been decoded.

- (BOOL) hasMoreFrames;

// Display a descriptive string that indicates frame source state

- (NSString*) description;

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block;

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime;

// FIXME: provide a way to set preventsDisplaySleepDuringVideoPlayback
// property on player objects unsed to implement playback.

// Stop playback by setting player rate to 0.0

- (void) stop;

@end
