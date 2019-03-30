//
//  AOVMTKView.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for license terms.
//
//  This object provides a base class for functionaity required
//  on top of a plain MTKView. This view adds support for
//  rendering from a CoreVideo pixel buffer. A regular RGB (24 BPP)
//  or a special purpose RGBA (32 BPP alpha channel) source can
//  be rendered into this Metal view.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;
@import MetalKit;

#import <MetalKit/MTKView.h>

#import "AOVFrame.h"
#import "AOVFrameSource.h"

// AOVMTKView extends MTKView

@interface AOVMTKView : MTKView <MTKViewDelegate>

// Previous frame, ref to the previous frame is dropped as
// soon as the next frame is delivered.

@property (nonatomic, retain) AOVFrame *prevFrame;

// Frame currently being displayed

@property (nonatomic, retain) AOVFrame *currentFrame;

// Protocol that defines how AOVFrame objects are loaded,
// the implementation is invoked from a display linked timer
// to load the next frame of video data to be displayed.

@property (nonatomic, retain) id<AOVFrameSource> frameSource;

// Configure view properties after view has been loaded from the NIB.
// Returns TRUE on success, otherwise FALSE is something went wrong.

- (BOOL) configure;

// This method is invoked when the next frame of video is available.

- (void) nextFrameReady:(AOVFrame*)nextFrame;

@end
