//
//  AOVGamma.h
//
//  Created by Mo DeJong on 12/26/18.
//
//  Indicate the type of gamma used with BT.709 matrix multiplication.

typedef enum {
  AOVGammaSRGB = 0, // default
  AOVGammaApple,
  AOVGammaLinear
} AOVGamma;
