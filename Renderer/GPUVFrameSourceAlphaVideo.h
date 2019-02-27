//
//  GPUVFrameSourceAlphaVideo.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  GPUVFrameSourceAlphaVideo class implements the GPUVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

#import "GPUVFrameSource.h"
#import "GPUVFrameSourceVideo.h"

@interface GPUVFrameSourceAlphaVideo : NSObject <GPUVFrameSource>

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// Init from pair of asset names

- (BOOL) loadFromAssets:(NSString*)resFilename alphaResFilename:(NSString*)resAlphaFilename;

// Init from asset or remote URL

- (BOOL) loadFromURLs:(NSURL*)URL alphaURL:(NSURL*)alphaURL;

- (NSString*) description;

// Kick of play operation

- (void) play;

@end
