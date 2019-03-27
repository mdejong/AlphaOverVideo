# AlphaOverVideo

iOS alpha channel video player library implemented on top of Metal

## Overview

This project implements a high performance interface to real-time rendering of alpha channel video as well as regular (opaque) video. The render layer is implemented using MetalKit and makes use of Metal shaders to decode and rescale video with the maximum possible performance on modern 64 bit iOS devices. As of iOS 12, the minimum device requirements are a 64 bit device that supports Metal. The MetalKit framework is leveraged to support rendering directly into a MTKView which can then be managed the same as any other UIView. Seamless looping and seamless transition from one video clip to another is supported.

## Status

Both BT.709 encoded H.264 video and an advanced new sRGB gamma curve encoding are supported.

## Decoding Speed

The Metal implementation renders YCbCr data as RGB pixels and is able to execute quickly enough to run full speed at 30 FPS, even on the first 64 bit A7 devices! On an A8 iPhone device both RGB+A mixing and video rescaling executes in under 2 ms.

## Implementation

See examples for source code that creates player objects with 24 BPP or 32 BPP videos.
