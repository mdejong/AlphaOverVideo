//
//  GPUVFrame.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  This object provides a wrapper for a single frame of video
//  as a NSObject instance. This object can be stored in an
//  NSArray or NSDictionary and it will maintain reference counts
//  for contained Core Video pixel buffers.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

// GPUVFrame class

@interface GPUVFrame : NSObject

@property (nonatomic, assign) CVPixelBufferRef yCbCrPixelBuffer;
@property (nonatomic, assign) CVPixelBufferRef alphaPixelBuffer;

// The frame number is calculated from the presentation timestamp
// in the video stream.

@property (atomic, assign) int frameNum;

- (NSString*) description;

// Given an item time calculate the corresponding integer frame number in the range (0, N-1)
//
// For example:
// 0.10 with frameDuration = 0.33 -> 0
// 0.33 with frameDuration = 0.33 -> 1
// 0.60 with frameDuration = 0.33 -> 2

+ (int) calcFrameNum:(float)itemTime frameDuration:(float)frameDuration;

@end
