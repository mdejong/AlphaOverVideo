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
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// This block is invoked on the main thread after the source has finished
// decoding the item.

@property (nonatomic, copy, nullable) void (^finishedBlock)(void);

// Init from asset name

- (BOOL) loadFromAsset:(NSString*)resFilename;

// Init from asset or remote URL

- (BOOL) loadFromURL:(NSURL*)URL;

- (NSString*) description;

// Kick of play operation

- (void) play;

// Kick of play operation where the zero time implicitly
// gets synced to the indicated host time. This means
// that 2 different calls to play on two different
// players will start in sync.

- (void) play:(CFTimeInterval)syncTime;

// Define a CMTimescale that will be used by the player, this
// implicitly assumes that the timeline has a rate of 0.0
// and that the caller will start playback by setting the
// timescale rate.

- (void) useMasterClock:(CMClockRef)masterClock;

- (void) seekToTimeZero;

@end
