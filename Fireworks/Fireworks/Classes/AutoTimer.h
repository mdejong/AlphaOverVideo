//  Created by Moses DeJong on 12/01/11.
//  Placed in the public domain.

/*
 * This AutoTimer class contains a instance of a NSTimer that is automatically canceled
 * when the containing AutoTimer object is deallocated. This class makes use of a timer
 * much easier because the developer does not need to remember to invoke invalidate
 * when the containing object is deallocated.
 */

#import <Foundation/Foundation.h>

/*----------------------------------------------------------------------------
 Interface:   AutoTimer
 -----------------------------------------------------------------------------*/

@interface AutoTimer : NSObject
{
  NSTimer *m_timer;
}

@property (nonatomic, retain) NSTimer *timer;

+ (AutoTimer*) autoTimerWithTimeInterval:(NSTimeInterval)seconds
                                  target:(id)target
                                selector:(SEL)aSelector
                                userInfo:(id)userInfo
                                 repeats:(BOOL)repeats;

@end
