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

// GPUVMTKView extends MTKView

@interface GPUVMTKView : MTKView

// Configure view properties after view has been loaded from the NIB

- (void) configure;

@end
