//
//  AOVPlayer.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  This object is initialized with a specific constructor
//  to indicate if a video is 24 BPP or 32 BPP (alpha channel)
//  video.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

#import "AOVFrameSource.h"

// AOVFrame class

@interface AOVPlayer : NSObject

@property (nonatomic, assign) BOOL hasAlphaChannel;

// Protocol that defines how AOVFrame objects are loaded,
// the implementation is invoked from a display linked timer
// to load the next frame of video data to be displayed.

@property (nonatomic, retain) id<AOVFrameSource> frameSource;

/*

// Create player with a single asset, at the
// end of the clip playback is stopped.

+ (AOVPlayer*) playerWithClip:(NSURL*)assetURL;

// Create player with multiple assets, the clips
// are played with seamless transitions between
// each clip. Playback is stopped after each
// clip has been played.

+ (AOVPlayer*) playerWithClips:(NSArray*)assetURLs;

// Create player with a single asset, this asset
// is played with seamless looping, over and over.

+ (AOVPlayer*) playerWithLoopedClip:(NSURL*)assetURL;

// Create player with multiple assets, seamless looping
// is used from clip to clip and the entire set of
// clips is looped at the end.

+ (AOVPlayer*) playerWithLoopedClips:(NSArray*)assetURLs;
 
*/

+ (AOVPlayer*) playerWithLoopedClips:(NSArray*)assetURLs;

// Create player with a single asset, at the
// end of the clip playback is stopped.

- (NSString*) description;

// Create NSURL given an asset filename.

+ (NSURL*) urlFromAsset:(NSString*)resFilename;

@end
