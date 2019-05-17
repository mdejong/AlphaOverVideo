//
//  AppDelegate.h
//  Fireworks
//
//  Created by Mo DeJong on 10/3/15.
//  Copyright © 2019 Mo DeJong. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MediaManager;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) MediaManager *mediaManager;

@end

