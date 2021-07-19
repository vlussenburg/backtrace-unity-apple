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

// oom attachments
NSMutableArray* _oomAttachments;

NSTimeInterval _lastUpdateTime;

// determine if debugger is available or not
bool _debugMode;

- (instancetype) initWithCrashReporter:(PLCrashReporter *)reporter andAttributes:(BacktraceAttributes *)attributes andApi:(BacktraceApi *) api andAttachments:(NSMutableArray*) attachments {
    if (self = [super init]) {
        _lastUpdateTime = 0;
        _attributes = attributes;
        _crashReporter = reporter;
        _backtraceApi = api;
        _oomAttachments = attachments;
        _applicationState = [NSMutableDictionary dictionary];
        _debugMode = [Utils isDebuggerAttached];
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
    [_applicationState setObject:_oomAttachments forKey:@"resource-attachments"];
    [_applicationState setObject:[[NSProcessInfo processInfo] operatingSystemVersionString] forKey:@"osVersion"];
    [_applicationState setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"appVersion"];
    [_applicationState setObject:[NSNumber numberWithBool:_debugMode] forKey:@"debuggerEnabled"];
}
/**
 send pending oom reports to Backtrace
 */
- (void)sendOomReports {
    NSString* statusPath = [Utils getDefaultOomStatusPath];
    // check if crash happened in the previous session
    if([_crashReporter hasPendingCrashReport]) {
        return;
    }
    NSFileManager* manager = [NSFileManager defaultManager];
    if([manager fileExistsAtPath:statusPath] == NO) {
        return;
    }
    
    NSDictionary* state= [NSDictionary dictionaryWithContentsOfFile:statusPath];
    if(!state) {
        return;
    }
   
    if (![self shouldReportOom:state]) {
        [OomWatcher cleanup];
        return;
    }
    
    NSData* resource = [state objectForKey:@"resource"];
    if(resource == nil) {
        resource = [_crashReporter generateLiveReport];
    }
    
    NSLog(@"Backtrace: App was closed due to OutOfMemory exception. Reporting state to Backtrace.");
    
   NSMutableArray* attachments = [NSMutableArray array];
    if([state objectForKey:@"resource-attachments"] != nil) {
       attachments = [state objectForKey:@"resource-attachments"];
    }
    
    NSMutableDictionary* attributes = [state objectForKey:@"resource-attributes"];
    if(attributes == nil) {
        attributes = [BacktraceAttributes getCrashAttributes];
        [attributes setObject:@"OOMException: Out of memory detected. No memory warning was detected."  forKey:@"error.message"];
        [attributes setObject:@"Low memory"  forKey:@"error.type"];
        [attributes setObject:@"OOMException" forKey:@"classifiers"];
    }
    
    [_backtraceApi upload:resource withAttributes: attributes andAttachments:attachments  andCompletionHandler:^(bool shouldRemove) {
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
