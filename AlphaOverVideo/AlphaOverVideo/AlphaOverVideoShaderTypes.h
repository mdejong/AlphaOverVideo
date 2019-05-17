//
//  AlphaOverVideoShaderTypes.h
//
//  See license.txt for license terms.
//
//  This header contains symbols shared between C and Metal shaders.

#ifndef AlphaOverVideoShaderTypes_h
#define AlphaOverVideoShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum AAPLVertexInputIndex
{
    AAPLVertexInputIndexVertices     = 0,
} AAPLVertexInputIndex;

// Texture index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API texture set calls
typedef enum
{
    AAPLTextureIndexBaseColor = 0,
} AAPLTextureIndex;

typedef enum
{
  AAPLTextureIndexYPlane = 0,
  AAPLTextureIndexCbCrPlane = 1,
  AAPLTextureIndexAlphaPlane = 2,
} AAPLTextureYCbCrIndex;

//  This structure defines the layout of each vertex in the array of vertices set as an input to our
//    Metal vertex shader.  Since this header is shared between our .metal shader and C code,
//    we can be sure that the layout of the vertex array in the code matches the layout that
//    our vertex shader expects
typedef struct
{
    // Positions in pixel space (i.e. a value of 100 indicates 100 pixels from the origin/center)
    vector_float2 position;

    // 2D texture coordinate
    vector_float2 textureCoordinate;
} AAPLVertex;

#endif // AlphaOverVideoShaderTypes_h