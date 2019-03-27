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

// Given a presentation time calculate the corresponding integer frame number in the range (0, N-1)

+ (int) calcFrameNum:(float)presentationTime fps:(float)fps;

@end
