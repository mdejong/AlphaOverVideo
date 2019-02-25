//
//  GPUVFrameSource.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  This frame source protocol defines a generic interface
//  that can be implemented by any class in order to generate
//  GPUVFrame objects that can be consumed by a GPUVMTKView.

@import Foundation;
@import AVFoundation;

#import "GPUVFrame.h"

// GPUVFrameSource protocol

@protocol GPUVFrameSource

// Given a host time offset, return a GPUVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.

- (GPUVFrame*) frameForHostTime:(CFTimeInterval)hostTime;

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been decoded.

- (BOOL) hasMoreFrames;

// Display a descriptive string that indicates frame source state

- (NSString*) description;

@end
