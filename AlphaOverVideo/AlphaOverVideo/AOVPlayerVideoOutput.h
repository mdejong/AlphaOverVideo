//
//  AOVPlayerVideoOutput.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  AOVFrameSourceVideo class implements the AOVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

#import "AOVFrame.h"

NS_ASSUME_NONNULL_BEGIN

@interface AOVPlayerVideoOutput : NSObject <AVPlayerItemOutputPullDelegate>

@property (nonatomic, copy, nullable) NSString *uid;

@property (nonatomic, assign) CFTimeInterval syncTime;
@property (nonatomic, assign) float playRate;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// If a reported time is larger than this time, then on the final frame

@property (nonatomic, assign) CFTimeInterval finalFrameTime;

// Load time is about a second before the end of the clip

@property (nonatomic, assign) CFTimeInterval lastSecondFrameTime;
@property (nonatomic, assign) float lastSecondFrameDelta;

@property (nonatomic, retain, null_unspecified) AVPlayer *player;
@property (nonatomic, retain, null_unspecified) AVPlayerItem *playerItem;
@property (nonatomic, retain, null_unspecified) AVPlayerItemVideoOutput *playerItemVideoOutput;
@property (nonatomic, retain, null_unspecified) dispatch_queue_t playerQueue;

@property (nonatomic, readonly) BOOL isReadyToPlay;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isFinishedPlaying;

@property (nonatomic, assign) BOOL isAssetAsyncLoaded;

// TRUE is looping N assets and this element is not the initial asset

@property (nonatomic, assign) BOOL secondaryLoopAsset;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// In the tricky race condition case where a video is prerolled but it does
// not start before the end of the loop condition then defer starting
// the video until the asset is actually ready to play.

@property (nonatomic, copy, nullable) void (^asyncReadyToPlayBlock)(void);

// This block will be invoked on the main thread when video playback
// is finished. For a single video, this is at the end of the video.
// For a set of clips, the finished callback is invoked after all
// clips are finished (including a set number of loops)

@property (nonatomic, copy, nullable) void (^videoPlaybackFinishedBlock)(void);

- (NSString*) description;

- (void) registerForItemNotificaitons;

// This method is invoked when the "tracks" data has become ready

- (BOOL) asyncTracksReady:(AVAsset*)asset;

- (void) stop;

- (void) endOfLoop;

- (void) useMasterClock:(CMClockRef)masterClock;

- (void) seekToTimeZero;

// Kick of play operation where the zero time implicitly
// gets synced to the indicated host time. This means
// that 2 different calls to play on two different
// players will start in sync.

- (void) play:(CFTimeInterval)syncTime;

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block;

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime;

// Directly set the play rate along with the self.isPlaying property

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime;

@end

NS_ASSUME_NONNULL_END

