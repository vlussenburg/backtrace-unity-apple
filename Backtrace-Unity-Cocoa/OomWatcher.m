#import <Foundation/Foundation.h>
#include "OomWatcher.h"
#include "Utils.h"

@implementation OomWatcher

// current application state
NSMutableDictionary* _applicationState;

// reporter
PLCrashReporter* _crashReporter;

// attributes
BacktraceAttributes* _attributes;

// http client instance
BacktraceApi* _backtraceApi;

NSTimeInterval _lastUpdateTime;

- (instancetype) initWithCrashReporter:(PLCrashReporter *)reporter andAttributes:(BacktraceAttributes *)attributes andApi:(BacktraceApi *) api {
    if (self = [super init]) {
        _lastUpdateTime = 0;
        _attributes = attributes;
        _crashReporter = reporter;
        _backtraceApi = api;
        _applicationState = [NSMutableDictionary dictionary];
        [self startOomIntegration];
    }
    
    return self;
}

- (void) startOomIntegration {
    [self sendOomReports];
    [self setDefaultApplicationState];
    [self saveApplicationState];
}

- (void) backgroundNotification {
    [_applicationState setObject:@"background" forKey:@"state"];
    [self saveApplicationState];
}

- (void) foregroundNotification {
    [_applicationState setObject:@"foreground" forKey:@"state"];
    [self saveApplicationState];
}

- (void) saveLowMemoryState {
     NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if( (currentTime - _lastUpdateTime) < 120) {
        _lastUpdateTime = currentTime;
        return;
    }
    
    NSLog(@"Backtrace: Received a memory warning message. Saving application state.");
    _lastUpdateTime = currentTime;
    // generate report
    [_applicationState setObject: [_crashReporter generateLiveReport] forKey:@"resource"];
    
    NSMutableDictionary *attributes = [BacktraceAttributes getCrashAttributes];
    [attributes setObject:@"OOMException: Out of memory detected."  forKey:@"error.message"];
    [attributes setObject:@"Low memory"  forKey:@"error.type"];
    [attributes setObject:[_applicationState objectForKey:@"state"]  forKey:@"state"];
    [attributes setObject:@"OOMException" forKey:@"classifiers"];
    
    [_applicationState setObject:attributes forKey:@"resource-attributes"];
    [self saveApplicationState];
    
}

/**
 set default application state
 */
- (void) setDefaultApplicationState {
    [_applicationState setObject:@"foreground" forKey:@"state"];
    [_applicationState setObject:[[NSProcessInfo processInfo] operatingSystemVersionString] forKey:@"osVersion"];
    [_applicationState setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"appVersion"];
    [_applicationState setObject:[NSNumber numberWithBool:[Utils isDebuggerAttached]] forKey:@"debuggerEnabled"];
}
/**
 send pending oom reports to Backtrace
 */
- (void)sendOomReports {
    NSString* statusPath = [Utils getDefaultOomStatusPath];
    NSFileManager* manager = [NSFileManager defaultManager];
    if([manager fileExistsAtPath:statusPath] == NO) {
        return;
    }
    
    NSDictionary* state= [NSDictionary dictionaryWithContentsOfFile:statusPath];
    if(!state) {
        return;
    }
    
    NSData* resource = [state objectForKey:@"resource"];
    // memory warning didn't occur in last session
    if(resource == nil) {
        return;
    }
   
    if (![self shouldReportOom:state]) {
        [OomWatcher cleanup];
        return;
    }
    
     NSLog(@"Backtrace: App was closed because of OutOfMemory exception. Reporting state to Backtrace.");
    [_backtraceApi upload:resource withAttributes: [state objectForKey:@"resource-attributes"]  andCompletionHandler:^(bool shouldRemove) {
        if(!shouldRemove) {
            NSLog(@"Backtrace: Cannot report OOM report");
        }
    }];
}


// decide if ios integration should send oom report to Backtrace
- (BOOL) shouldReportOom: (NSDictionary*) state{
    NSString* osVersion = [state objectForKey:@"osVersion"];
    if(osVersion == nil || ![osVersion isEqualToString: [[NSProcessInfo processInfo] operatingSystemVersionString]]) {
        return NO;
    }
    
    NSString* appVersion = [state objectForKey:@"appVersion"];
    if(appVersion == nil || ![appVersion isEqualToString: [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]]) {
        return NO;
    }
    
    NSNumber* isDebuggerEnabled = [state objectForKey:@"debuggerEnabled"];
    if([isDebuggerEnabled isEqualToNumber:@1]) {
        return NO;
    }
    return YES;
}

// cleanup Oom integration
+ (void) cleanup {
    NSString* statusPath = [Utils getDefaultOomStatusPath];
    NSFileManager* manager = [NSFileManager defaultManager];
    if(![manager fileExistsAtPath:statusPath]) {
        return;
    }
    
    NSError *error;
    [manager removeItemAtPath:statusPath error: &error];
}


- (void) saveApplicationState {
    NSString* statusPath = [Utils getDefaultOomStatusPath];
    [_applicationState writeToFile:statusPath atomically:YES];
}
@end
