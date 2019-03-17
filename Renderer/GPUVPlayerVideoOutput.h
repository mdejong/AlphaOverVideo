//
//  GPUVPlayerVideoOutput.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//
//  GPUVFrameSourceVideo class implements the GPUVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

#import "GPUVFrame.h"

@interface GPUVPlayerVideoOutput : NSObject <AVPlayerItemOutputPullDelegate>

@property (nonatomic, copy) NSString *uid;

@property (nonatomic, assign) CFTimeInterval syncTime;
@property (nonatomic, assign) float playRate;

// The integer count of the number of times the video has looped.
// This value starts out as zero, it then increases each time
// the active item changes.

@property (nonatomic, readonly) int loopCount;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// If a reported time is larger than this time, then on the final frame

@property (nonatomic, assign) CFTimeInterval finalFrameTime;

@property (nonatomic, retain) AVPlayer *player;
@property (nonatomic, retain) AVPlayerItem *playerItem;
@property (nonatomic, retain) AVPlayerItemVideoOutput *playerItemVideoOutput;
@property (nonatomic, retain) dispatch_queue_t playerQueue;

@property (nonatomic, assign) BOOL isReadyToPlay;
@property (nonatomic, assign) BOOL isPlaying;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

- (NSString*) description;

// This method is invoked when the "tracks" data has become ready

- (BOOL) asyncTracksReady:(AVAsset*)asset;

- (void) stop;

- (void) endOfLoop;

- (void) useMasterClock:(CMClockRef)masterClock;

- (void) seekToTimeZero;

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block;

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime;

@end
