# AlphaOverVideo

iOS alpha channel video player library implemented on top of Metal

## Overview

This project implements a high performance interface to real-time rendering of alpha channel video as well as regular (opaque) video. The render layer is implemented using MetalKit and makes use of Metal shaders to decode and rescale video with the maximum possible performance on modern 64 bit iOS devices. As of iOS 12, the minimum device requirements are a 64 bit device that supports Metal. The MetalKit framework is leveraged to support rendering directly into a MTKView which can then be managed the same as any other UIView. Seamless looping and seamless transition from one video clip to another is supported.

## Status

H.264 video encoded with BT.709 gamma as well as an advanced new sRGB gamma are supported. Note that BT.601 encoding is explicitly not supported, the long ongoing nightmare of broken or mis-detected BT.601 vs BT.709 encoding parameters must end!

## Decoding Speed

The Metal implementation renders YCbCr data as RGB pixels and is able to execute quickly enough to run full speed at 30 FPS, even on the first 64 bit A7 devices! On an A8 iPhone device both RGB+A mixing and video rescaling executes in under 2 ms.

## Implementation

See examples for source code that creates player objects with 24 BPP or 32 BPP videos.

## Encoding

To encode your own video, compile the srgb_to_bt709 command line target use it and convert a series of PNG images to a .y4m file.

This command line encodes a 24 BPP video with an Apple specific BT.709 gamma curve.

$ srgb_to_bt709 -gamma apple -frames F0001.png -fps 30 Example.y4m

Then encode with ffmpeg+x264 using the scripts in the FFMPEG directory. The following command line uses the default crf quality setting of 23 and the BT.709 specific script.

$ ext_ffmpeg_encode_bt709_crf.sh Example.y4m Example.m4v 23

To create an alpha channel video, use 32 BPP input PNG images and pass -alpha 1 on command line. Note that the gamma is always srgb when using alpha channel video.

$ srgb_to_bt709 -alpha 1 -frames F0001.png -fps 30 ExampleAlpha.y4m

An alpha channel video is written as ExampleAlpha.y4m and also a second file named Example_alpha.y4m. The RGB pixels are premultiplied and written with srgb gamma. The ALPHA pixels are written with linear gamma. Two encoding scripts invocations are needed to encode to M4V container format videos.

$ ext_ffmpeg_encode_srgb_crf.sh Example.y4m Example.m4v 23

$ ext_ffmpeg_encode_linear_crf.sh Example_alpha.y4m Example_alpha.m4v 23

The large temporary .y4m files can be deleted once compressed H.264 files have been encoded.

One can also increase the crf value for more compression (smaller file size). The "right" crf level is subjective and depends on the input video. The more lossy the smaller the output file but the more the visual quality is reduced.

The H.264 files (as .m4v container format can be played in QuicktimeX player.

Attach the output of this encoding process to the iOS application bundle so that the files can be loaded in an iOS app.
