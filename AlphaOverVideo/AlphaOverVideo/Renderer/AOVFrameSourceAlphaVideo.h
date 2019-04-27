//
//  AOVFrameSourceAlphaVideo.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  AOVFrameSourceAlphaVideo class implements the AOVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;



#import "AOVFrameSource.h"
#import "AOVFrameSourceVideo.h"

NS_ASSUME_NONNULL_BEGIN

@interface AOVFrameSourceAlphaVideo : NSObject <AOVFrameSource>

@property (nonatomic, assign) CFTimeInterval syncTime;
@property (nonatomic, assign) float playRate;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// This flag is true once the last frame of a video has been decoded,
// the flag is cleared after the next frame after the loop has restarted
// has been successfully decoded.

@property (nonatomic, readonly) int isLooping;

// The integer count of the number of times the video has looped.
// This value starts out as zero, it then increases each time
// the active item changes.

@property (nonatomic, readonly) int loopCount;

// The maximum number of times a clip or a collection of clips will
// be looped. When zero this indicates that playback will be stopped
// after loop N completes.

@property (nonatomic, assign) int loopMaxCount;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// Callback when stop has been invoked at end of clip(s) or loops

@property (nonatomic, copy, nullable) void (^videoPlaybackFinishedBlock)(void);

// Returns TRUE when video is playing
@property (nonatomic, readonly) BOOL isPlaying;

// Return TRUE when video has been playing and has reache the end of
// a clip or has looped clips the maximum number of times.
@property (nonatomic, readonly) BOOL isFinishedPlaying;

// Init from an array of NSURL objects, loads the first
// RGB and Alpha URLS from urlArr[0]

- (BOOL) loadFromURLs:(NSArray*)urlArr;

- (NSString*) description;

// Kick of play operation

- (void) play;

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block;

// Stop playback by setting player rate to 0.0

- (void) stop;

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime;

// Invoke player setRate to actually begin playing back a video
// source once playWithPreroll invokes the block callback
// with a specific host time to sync to.

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime;

- (void) useMasterClock:(CMClockRef)masterClock;


@end

NS_ASSUME_NONNULL_END
