//
//  GPUVMTKView.m
//
//  Created by Mo DeJong on 2/22/19.
//
//  See license.txt for BSD license terms.
//

#import "GPUVMTKView.h"

// Private API

@interface GPUVMTKView ()

@end

@implementation GPUVMTKView

- (void) dealloc
{
  return;
}

- (void) configure
{
  self.enableSetNeedsDisplay = FALSE;
  self.paused = TRUE;
}

- (void)drawRect:(CGRect)rect
{
//  if (self.frameObj != nil) {
//    [self displayFrame];
//  } else {
//    glClearColor(0.0, 0.0, 0.0, 1.0);
//    glClear(GL_COLOR_BUFFER_BIT);
//  }

  [self displayFrame];
}

// Invoked to execute Metal

- (void) displayFrame
{
  //NSLog(@"displayFrame %@", frame);
  
  [self.delegate drawInMTKView:self];
}

- (NSString*) description
{
  int width = (int) -1;
  int height = (int) -1;
  
  return [NSString stringWithFormat:@"GPUVMTKView %p %dx%d",
          self,
          width,
          height];
}

@end
