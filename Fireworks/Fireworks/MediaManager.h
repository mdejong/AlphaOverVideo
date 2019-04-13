//
//  MediaManager.h
//  Fireworks
//
//  Created by Mo DeJong on 10/3/15.
//  Copyright © 2015 helpurock. All rights reserved.
//
//  This object holds URL references to media data that would be played
//  for each firework.

@import UIKit;
@import AlphaOverVideo;

@interface MediaManager : NSObject

// RGB videos
@property (nonatomic, retain) NSURL *wheelURL;
@property (nonatomic, retain) NSURL *redURL;

// RGBA videos
@property (nonatomic, retain) NSArray<NSURL*> *L12URL;
@property (nonatomic, retain) NSArray<NSURL*> *L22URL;
@property (nonatomic, retain) NSArray<NSURL*> *L32URL;
@property (nonatomic, retain) NSArray<NSURL*> *L42URL;
@property (nonatomic, retain) NSArray<NSURL*> *L52URL;
@property (nonatomic, retain) NSArray<NSURL*> *L62URL;
@property (nonatomic, retain) NSArray<NSURL*> *L92URL;
@property (nonatomic, retain) NSArray<NSURL*> *L112URL;

// constructor

+ (MediaManager*) mediaManager;

- (void) makeURLs;

// Kick off background loading thread. This call does not block, but
// it can be useful to avoid kicking off threads until the main app
// loop is up and runnning (do not call from viewDidLoad init path
// for example.

- (void) startAsyncLoading;

// Check to see if all loaders are ready now

- (BOOL) allLoadersReady;

// Return array of all alpha channel fireworks media URLs.

- (NSArray*) getFireworkURLs;

@end

