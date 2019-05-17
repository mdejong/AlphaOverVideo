//
//  AOVPlayer.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//

#import "AOVPlayer.h"

#import <QuartzCore/QuartzCore.h>

#import "AOVFrameSource.h"
#import "AOVFrameSourceAlphaVideo.h"
#import "AOVFrameSourceVideo.h"

// Private API

@interface AOVPlayer ()

@property (nonatomic, assign) int frameNum;

@property (nonatomic, assign) BOOL hasAlphaChannel;

// Protocol that defines how AOVFrame objects are loaded,
// the implementation is invoked from a display linked timer
// to load the next frame of video data to be displayed.

@property (nonatomic, retain) id<AOVFrameSource> frameSource;

@end

@implementation AOVPlayer

// Given an array of clips, either NSURL objects or pairs of
// NSURL objects in a NSArray, validate the input and return
// an array that represents the clips to loop. Return nil
// if validation fails. Note the case where only 1 item
// is included in the array, this is converted to

+ (BOOL) validateClips:(NSArray*)assetURLs clipSubCountPtr:(int*)clipSubCountPtr
{
  int num = (int) assetURLs.count;
  
  if (num == 0) {
    return FALSE;
  }
  
  // If first clip argument is RGB+A pair then all the others
  // should also have the same subclip count.
  
  int subCount = -1;
  
  for ( id obj in assetURLs ) {
    if ([obj isKindOfClass:NSURL.class]) {
      if (subCount == -1) {
        subCount = 1;
      } else if (subCount == 1) {
        // nop
      } else {
        NSAssert(FALSE, @"subCount is %d when single URL argument found", subCount);
        return FALSE;
      }
    } else if ([obj isKindOfClass:NSArray.class]) {
      NSArray *pair = (NSArray *) obj;
      int pairCount = (int)[pair count];
      if (pairCount != 2) {
        NSAssert(pairCount == 2, @"should be URL pair but found %d elements", pairCount);
        return FALSE;
      }
      if (subCount == -1) {
        subCount = 2;
      }
    } else {
      NSAssert(FALSE, @"unknown type for assetURLs element \"%@\"", obj);
      return FALSE;
    }
  }
  
  *clipSubCountPtr = subCount;
  
  return TRUE;
}

// Create player with a single asset, at the
// end of the clip, playback is stopped.
// This method accepts either a NSURL*
// or a NSArray tuple that contains two NSURLs.

+ (AOVPlayer*) playerWithClip:(id)assetURLOrPair
{
  return [self playerWithLoopedClipsPrivate:@[assetURLOrPair] looped:FALSE loopMaxCount:1];
}

+ (AOVPlayer*) playerWithClips:(NSArray*)assetURLs
{
  // Seamless loop the number of times needed to play each clip once
  int loopMaxCount = (int) assetURLs.count;
  return [self playerWithLoopedClipsPrivate:assetURLs looped:FALSE loopMaxCount:loopMaxCount];
}

+ (AOVPlayer*) playerWithLoopedClip:(id)assetURLOrPair
{
  return [self playerWithLoopedClipsPrivate:@[assetURLOrPair] looped:TRUE loopMaxCount:0];
}

+ (AOVPlayer*) playerWithLoopedClips:(NSArray*)assetURLs
{
  return [self playerWithLoopedClipsPrivate:assetURLs looped:TRUE loopMaxCount:0];
}

+ (AOVPlayer*) playerWithLoopedClipsPrivate:(NSArray*)assetURLs
                                     looped:(BOOL)looped
                               loopMaxCount:(int)loopMaxCount
{
  int subCount;
  BOOL valid = [self validateClips:assetURLs clipSubCountPtr:&subCount];
  if (!valid) {
    return nil;
  }
  
  int num = (int) assetURLs.count;
  
  NSMutableArray *mURLs = [NSMutableArray array];
  
  // Note that (num == 0) is handled above
  
  if (num == 1 && looped) {
    // One clip will be initialized as using 2 copies of the url
    id url = assetURLs[0];
    [mURLs addObject:url];
    [mURLs addObject:url];
  } else {
    // Multiple urls passed as-is
    [mURLs addObjectsFromArray:assetURLs];
  }
  
  // If subCount is 1 then RGB clips, else RGB+A
  
  AOVPlayer *player = [[AOVPlayer alloc] init];
  
  player.hasAlphaChannel = (subCount == 2);
  
  id<AOVFrameSource> frameSource = nil;
  
  if (player.hasAlphaChannel) {
    // RGBA 32BPP alpha video
    AOVFrameSourceAlphaVideo *frameSourceAlphaVideo = [[AOVFrameSourceAlphaVideo alloc] init];
    frameSource = frameSourceAlphaVideo;
    
    BOOL result = [frameSourceAlphaVideo loadFromURLs:mURLs];
    if (result != TRUE) {
      return nil;
    }
  } else {
    // RGB 24BPP (opaque) video
    AOVFrameSourceVideo *frameSourceVideo = [[AOVFrameSourceVideo alloc] init];
    frameSource = frameSourceVideo;
    
    frameSourceVideo.playedToEndBlock = nil;
    frameSourceVideo.finalFrameBlock = nil;
    
    frameSourceVideo.uid = @"rgb";
    
    __weak typeof(frameSourceVideo) weakFrameSourceVideo = frameSourceVideo;
    
    frameSourceVideo.finalFrameBlock = ^{
      //NSLog(@"AOVFrameSourceVideo.finalFrameBlock %.3f", CACurrentMediaTime());
      [weakFrameSourceVideo restart];
    };
    
    BOOL result = [frameSourceVideo loadFromURLs:mURLs];
    if (result != TRUE) {
      return nil;
    }
  }
  
  frameSource.loopMaxCount = loopMaxCount;
  
  // Define source for frames in terms of generic interface ref
  
  player.frameSource = frameSource;
  
  return player;
}

- (void) dealloc
{
  return;
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"AOVPlayer %p F=%05d",
          self,
          self.frameNum];
}

// Create NSURL given an asset filename.

+ (NSURL*) urlFromAsset:(NSString*)resFilename
{
  NSString *path = [[NSBundle mainBundle] pathForResource:resFilename ofType:nil];
  if (path == nil) {
    return nil;
  }
  
  NSURL *assetURL = [NSURL fileURLWithPath:path];
  return assetURL;
}


- (void) setVideoPlaybackFinishedBlock:(void (^)(void))videoPlaybackFinishedBlock
{
  self.frameSource.videoPlaybackFinishedBlock = videoPlaybackFinishedBlock;
}

@end
