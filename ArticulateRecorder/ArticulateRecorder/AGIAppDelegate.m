//
//  AGIAppDelegate.m
//  ArticulateRecorder
//
//  Created by Christopher Miller on 4/9/14.
//  Copyright (c) 2014 Articulate Global, Inc. All rights reserved.
//

#import "AGIAppDelegate.h"

@implementation AGIAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSLog(@"recordr app did finish launching");
    
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
