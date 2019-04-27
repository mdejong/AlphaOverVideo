//
//  AOVFrameSourceVideo.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  AOVFrameSourceVideo class implements the AOVFrameSource
//  protocol and provides an implementation that loads
//  frames from a video source via an AVPlayer instance.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

#import "AOVFrameSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface AOVFrameSourceVideo : NSObject <AOVFrameSource>

@property (nonatomic, copy, nullable) NSString *uid;

@property (nonatomic, assign) CFTimeInterval syncTime;
@property (nonatomic, assign) float playRate;

// The integer count of the number of times the video has looped.
// This value starts out as zero, it then increases each time
// the active item changes.

@property (nonatomic, readonly) int loopCount;

// The maximum number of times a clip or a collection of clips will
// be looped. When zero this indicates that playback will be stopped
// after loop N completes.

@property (nonatomic, assign) int loopMaxCount;

@property (nonatomic, assign) float FPS;
@property (nonatomic, assign) float frameDuration;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

// This block is invoked on the main thread once source video data
// has been loaded. This callback is invoked just once for a video
// source object and the block is set to nil once completed.

@property (nonatomic, copy, nullable) void (^loadedBlock)(BOOL success);

// This block is invoked when an item is played all the way to the end.
// This callback is invoked at the end of the display interval for the
// final frame of a specific clip. By default, this block will invoke
// the stop method so that a clip plays once and then stops playback.

@property (nonatomic, copy, nullable) void (^playedToEndBlock)(void);

// This block is invoked after the final frame for an item has been
// both decoded and displayed. When this callback is invoked, the
// final frame will continue to display for one more frameDuration
// interval.

@property (nonatomic, copy, nullable) void (^finalFrameBlock)(void);

// This block is invoked one second before the end of the clip.

@property (nonatomic, copy, nullable) void (^lastSecondFrameBlock)(void);
@property (nonatomic, assign) BOOL lastSecondFrameBlockInvoked;
@property (nonatomic, assign) float lastSecondFrameDelta;

// Callback when stop has been invoked at end of clip(s) or loops

@property (nonatomic, copy, nullable) void (^videoPlaybackFinishedBlock)(void);

// Returns TRUE when video is playing
@property (nonatomic, readonly) BOOL isPlaying;

// Return TRUE when video has been playing and has reache the end of
// a clip or has looped clips the maximum number of times.
@property (nonatomic, readonly) BOOL isFinishedPlaying;

// Init from array of URL assets

- (BOOL) loadFromURLs:(NSArray*)urlsArr;

- (NSString*) description;

// Kick of play operation

- (void) play;

// Kick of play operation where the zero time implicitly
// gets synced to the indicated host time. This means
// that 2 different calls to play on two different
// players will start in sync.

- (void) play:(CFTimeInterval)syncTime;

// restart will rewind and then play, in the case where the video is already
// playing then a call to restart will just rewind.

- (void) restart;

// Stop playback by setting player rate to 0.0

- (void) stop;

// Invoked a second before the end of the clip

- (void) lastSecond;

// Define a CMTimescale that will be used by the player, this
// implicitly assumes that the timeline has a rate of 0.0
// and that the caller will start playback by setting the
// timescale rate.

- (void) useMasterClock:(CMClockRef)masterClock;

- (void) seekToTimeZero;

// Initiate playback by preloading for a specific rate (typically 1.0)
// and invoke block callback.

- (void) playWithPreroll:(float)rate block:(void (^)(void))block;

// Invoke player setRate to actually begin playing back a video
// source once playWithPreroll invokes the block callback
// with a specific host time to sync to.

- (void) setRate:(float)rate atHostTime:(CFTimeInterval)atHostTime;

// Sync start will seek to the given time and then invoke
// a sync sync method to play at the given rate after
// aligning the given host time to the indicated time.

- (void) syncStart:(float)rate
          itemTime:(CFTimeInterval)itemTime
        atHostTime:(CFTimeInterval)atHostTime;

// The next 3 APIs map time to a specific video frame. The
// frameForHostTime API is the higher level interface where
// system "host" time is mapped to the item timeline and then
// the frame is looked up based on the item time. The
// itemTimeForHostTime and frameForItemTime APIs can be used
// to manually convert host time to item time and then item
// time can be used to lookup the specific frame.

// Given a host time offset, return a AOVFrame that corresponds
// to the given host time. If no new frame is avilable for the
// given host time then nil is returned.
// The hostPresentationTime indicates the host time when the
// decoded frame would be displayed.
// The presentationTimePtr pointer provides a way to query the
// DTS (display time stamp) of the decoded frame in the H.264 stream.
// Note that presentationTimePtr can be NULL.

- (nullable AOVFrame*) frameForHostTime:(CFTimeInterval)hostTime
                   hostPresentationTime:(CFTimeInterval)hostPresentationTime
                    presentationTimePtr:(nullable float*)presentationTimePtr;

// Map host time to item time for the current item.
// Note that kCMTimeInvalid is returned if the host
// time cannot be mapped to an item time yet due to
// the video stream not yet being ready to play.

- (CMTime) itemTimeForHostTime:(CFTimeInterval)hostTime;

// Get frame that corresponds to item time. The item time range is
// (0.0, (N * frameDuration))
// Note that hostTime is used only for debug output here

- (nullable AOVFrame*) frameForItemTime:(CMTime)itemTime
                               hostTime:(CFTimeInterval)hostTime
                   hostPresentationTime:(CFTimeInterval)hostPresentationTime
                    presentationTimePtr:(nullable float*)presentationTimePtr;

@end

NS_ASSUME_NONNULL_END
