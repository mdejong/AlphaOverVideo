//
//  GPUVMTKView.h
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
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

#include "GPUVFrame.h"

// GPUVMTKView extends MTKView

@interface GPUVMTKView : MTKView

// Previous frame, ref to the previous frame is dropped as
// soon as the next frame is delivered.

@property (nonatomic, retain) GPUVFrame *prevFrame;

// Frame currently being displayed

@property (nonatomic, retain) GPUVFrame *currentFrame;

// Configure view properties after view has been loaded from the NIB.
// Returns TRUE on success, otherwise FALSE is something went wrong.

- (BOOL) configure;

- (void) nextFrameReady:(GPUVFrame*)nextFrame;

@end
