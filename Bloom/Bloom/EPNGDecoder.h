//
//  EPNGDecoder.h
//
//  Created by Mo DeJong on 6/1/19.
//  See LICENSE for license terms.
//
//  Util class that implements decoding a data buffer from an embedded PNG
//  format. An iOS client rewraps a binary file as a PNG and then decodes
//  after pullint the image data from the asset catalog to take advantage
//  of app slicing to reduce downloaded app sizes.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface EPNGDecoder : NSObject

// Return unique file path in temp dir, pass in a template like
// @"videoXXXXXX.m4v" to define the path name tempalte. If
// tmpDir is nil then NSTemporaryDirectory() is used.
// If decodeCRC is not NULL then a CRC is calculated on
// the decoded buffer.

+ (NSURL*) saveEmbeddedAssetToTmpDir:(CGImageRef)cgImage
                          pathPrefix:(NSString*)pathPrefix
                              tmpDir:(NSString* _Nullable)tmpDir
                           decodeCRC:(int* _Nullable)decodeCRC;

@end

NS_ASSUME_NONNULL_END
