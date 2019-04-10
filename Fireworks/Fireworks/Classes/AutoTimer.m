//  Created by Moses DeJong on 12/01/11.
//  Placed in the public domain.

#import "AutoTimer.h"

@implementation AutoTimer

@synthesize timer = m_timer;

+ (AutoTimer*) autoTimerWithTimeInterval:(NSTimeInterval)seconds
                                  target:(id)target
                                selector:(SEL)aSelector
                                userInfo:(id)userInfo
                                 repeats:(BOOL)repeats
{
  AutoTimer *obj = [[AutoTimer alloc] init];

#if __has_feature(objc_arc)
#else
  obj = [obj autorelease];
#endif // objc_arc

  obj.timer = [NSTimer timerWithTimeInterval:seconds
                                      target:target
                                    selector:aSelector
                                    userInfo:userInfo
                                     repeats:repeats];
  
  [[NSRunLoop currentRunLoop] addTimer:obj.timer forMode: NSDefaultRunLoopMode];
  
  return obj;
}

- (void) dealloc
{
  [self.timer invalidate];
  self.timer = nil;
    
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

@end
