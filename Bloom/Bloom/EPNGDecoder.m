//
//  EPNGDecoder.m
//
//  Created by Mo DeJong on 6/1/19.
//  See LICENSE for license terms.
//

#import "EPNGDecoder.h"

#import <zlib.h>

// class EPNGDecoder

@implementation EPNGDecoder

+ (EPNGDecoder*) ePNGDecoder
{
  EPNGDecoder *obj = [[EPNGDecoder alloc] init];
  return obj;
}

// Return unique file path in temp dir, pass in a template like
// @"videoXXXXXX.m4v" to define the path name tempalte. If
// tmpDir is nil then NSTemporaryDirectory() is used.
// If decodeCRC is not NULL then a CRC is calculated on
// the decoded buffer.

+ (NSURL*) saveEmbeddedAssetToTmpDir:(CGImageRef)cgImage
                          pathPrefix:(NSString*)pathPrefix
                              tmpDir:(NSString*)tmpDir
                           decodeCRC:(int*)decodeCRC
{
  NSURL *url = nil;
  
  @autoreleasepool {
  
  int bitmapWidth = (int) CGImageGetWidth(cgImage);
  int bitmapHeight = (int) CGImageGetHeight(cgImage);
  int bitmapNumPixels = bitmapWidth * bitmapHeight;
  
  CGRect imageRect = CGRectMake(0, 0, bitmapWidth, bitmapHeight);
  
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
  
  int bitsPerComponent = 8;
  int numComponents = 1;
  int bitsPerPixel = bitsPerComponent * numComponents;
  int bytesPerRow = (int) (bitmapWidth * (bitsPerPixel / 8));
  
  CGBitmapInfo bitmapInfo = (CGBitmapInfo) kCGImageAlphaNone;
  
  // Create bitmap content with current image size and grayscale colorspace
  CGContextRef context = CGBitmapContextCreate(NULL, bitmapWidth, bitmapHeight, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  if (context == NULL) {
    return nil;
  }
  
  // Draw image into current context, with specified rectangle using context and colorspace.
  CGContextDrawImage(context, imageRect, cgImage);
  
  uint8_t *contextPtr = (uint8_t *) CGBitmapContextGetData(context);
    if (contextPtr == NULL) {
      return nil;
    }
  
  assert(CGBitmapContextGetBytesPerRow(context) == bytesPerRow);
    
    if ((0)) {
      uint8_t *pixelsPtr = (uint8_t *) contextPtr;
      
      for (int y = 0; y < bitmapHeight; y++) {
        for (int x = 0; x < bitmapWidth; x++) {
          uint8_t pixel = pixelsPtr[(y * bitmapWidth) + x];
          fprintf(stdout, "0x%02X ", pixel);
        }
        fprintf(stdout, "\n");
      }
    }
  
    // Walk backwards from the end of the buffer until a non-zero value is found.
    
    uint8_t *endPtr = contextPtr + bitmapNumPixels - 1;
    
    while ((endPtr != contextPtr) && (*endPtr == 0)) {
      endPtr--;
    }
    
    int bufferLength = (int) (endPtr - contextPtr + 1);
    
    NSData *rawBytes = [NSData dataWithBytes:contextPtr length:bufferLength];
    
    if ((0)) {
      uint8_t *pixelsPtr = (uint8_t *) rawBytes.bytes;
      int numPixels = (int) rawBytes.length;
      
      printf("zeros trimmed buffer contains %d bytes\n", numPixels);
      
      for (int i = 0; i < rawBytes.length; i++) {
        printf("bufffer[%d] = 0x%02X\n", i, pixelsPtr[i]);
      }
    }
  
  // Signature of decoded PNG data (optional)
  
  if (decodeCRC != NULL) {
    uint32_t crc = (uint32_t) crc32(0, (void*)rawBytes.bytes, (int)rawBytes.length);
    
    if ((1)) {
      printf("decode CRC 0x%08X based on %d input buffer bytes\n", crc, (int)rawBytes.length);
    }
    
    *decodeCRC = crc;
  }
  
  // Release colorspace, context and bitmap information
  //CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  
  NSString *tmpPath = [self getUniqueTmpDirPath:pathPrefix tmpDir:tmpDir];
  
  BOOL worked = [rawBytes writeToFile:tmpPath atomically:TRUE];
  
  if (worked == FALSE) {
    return nil;
  }
  
  url = [NSURL fileURLWithPath:tmpPath];
    
  }
  
  return url;
}

// Return unique file path in temp dir, pass in a template like
// @"videoXXXXXX.m4v" to define the path name tempalte. If
// tmpDir is nil then NSTemporaryDirectory() is used.

+ (NSString*) getUniqueTmpDirPath:(NSString*)pathPrefix tmpDir:(NSString*)tmpDir
{
  if (tmpDir == nil) {
    tmpDir = NSTemporaryDirectory();
  }
  
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:pathPrefix];
  
  // pathPrefix must end with 6 "XXXXXX" characters
  
  NSString *templateStr = @"XXXXXX";
  
  BOOL hasTemplate = [pathPrefix containsString:templateStr];
  
  if (!hasTemplate) {
    return nil;
  }
  
  NSRange range = [tmpPath rangeOfString:templateStr options:NSLiteralSearch|NSBackwardsSearch];
  
  // Get filename up to the end of the template
  
  NSRange rangeOfTemplate;
  rangeOfTemplate.location = 0;
  rangeOfTemplate.length = range.location + range.length;
  
  NSString *upToTemplateStr = [tmpPath substringWithRange:rangeOfTemplate];

  NSRange afterTemplate;
  afterTemplate.location = rangeOfTemplate.length;
  afterTemplate.length = [tmpPath length] - afterTemplate.location;
  
  NSString *afterTemplateStr = [tmpPath substringWithRange:afterTemplate];
  
  const char *rep = [upToTemplateStr fileSystemRepresentation];
  
  char *temp_template = strdup(rep);
  int largeFD = mkstemp(temp_template);
  NSString *largeFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:temp_template length:strlen(temp_template)];
  free(temp_template);
  NSAssert(largeFD != -1, @"largeFD");
  NSAssert(largeFileName, @"largeFileName");
  close(largeFD);
  unlink(temp_template);
  
  return [largeFileName stringByAppendingString:afterTemplateStr];
}

@end
