//
//  MetalBT709Gamma.h
//
//  Created by Mo DeJong on 12/26/18.
//
//  Given an input buffer of BT.709 encoded YCbCr data, decode
//  pixels into a sRGB texture.

typedef enum {
  MetalBT709GammaSRGB = 0, // default
  MetalBT709GammaApple,
  MetalBT709GammaLinear
} MetalBT709Gamma;
