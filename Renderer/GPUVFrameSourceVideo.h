//
//  GPUVFrameSourceVideo.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  GPUVFrameSourceVideo class implements the GPUVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

#import "GPUVFrameSource.h"

@interface GPUVFrameSourceVideo : NSObject <GPUVFrameSource>

@property (nonatomic, assign) float FPS;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// Init from asset name

- (BOOL) loadFromAsset:(NSString*)resFilename;

// Init from asset or remote URL

- (BOOL) loadFromURL:(NSURL*)URL;

- (NSString*) description;

// Kick of play operation

- (void) play;

@end
