#import <Foundation/Foundation.h>
#import "Backtrace.h"
#import "CrashReporter.h"
#import "BacktraceApi.h"
#import "Utils.h"
#import "OomWatcher.h"

#import <UIKit/UIKit.h>

@implementation Backtrace


/**
 PL Crash reporter instance
 */
PLCrashReporter* _crashReporter;

/**
 Backtrace API Instance - http client to send Backtrace Reports
 */
BacktraceApi* _backtraceApi;

/**
 Class responsible for storing and managing attributes
 */
BacktraceAttributes* _backtraceAttributes;

/**
 Backtrace OOM watcher instance
 */
OomWatcher* _oomWatcher;
/**
 Class instance
 */
static Backtrace *instance;

bool oomSupport;

static void onCrash(siginfo_t *info, ucontext_t *uap, void *context) {
    [OomWatcher cleanup];
    NSMutableDictionary *attributes = [BacktraceAttributes getCrashAttributes];
    
    NSString* errorMessage = [@"siginfo_t.si_signo:" stringByAppendingString:[@(info->si_signo) stringValue]];
    [attributes setObject:errorMessage  forKey:@"error.message"];
    NSString* reportPath =[Utils getDefaultReportPath];
    [attributes writeToFile:reportPath atomically:YES];
    NSLog(@"Backtrace: Received game crash. Storing attributes at path:%@", reportPath);
}

- (instancetype)initWithBacktraceUrl:(const char*) rawUrl andAttributes:(NSMutableDictionary*) attributes andOomSupport:(bool) enableOomSupport {
    if(instance != nil) {
        return instance;
    }
    
    if(!rawUrl) {
        NSLog(@"Backtrace: Backtrace URL is not available");
        return nil;
    }
    if( self = [super init]) {
        if(![Utils prepareCrashDirectory]) {
            NSLog(@"Backtrace: Cannot start integration - cannot create cache dir");
            return nil;
        }
        _backtraceAttributes = [[BacktraceAttributes alloc] initWithAttributes:attributes];
        _backtraceApi = [[BacktraceApi alloc] initWithBacktraceUrl:rawUrl];
        
        // initialize Crash reporter
        PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeBSD;
        PLCrashReporterSymbolicationStrategy symbolicationStrategy = PLCrashReporterSymbolicationStrategyAll;
        PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType: signalHandlerType
                                                                           symbolicationStrategy: symbolicationStrategy];
        _crashReporter = [[PLCrashReporter alloc] initWithConfiguration: config];
        
        PLCrashReporterCallbacks cb = {
            .version = 0,
            .context = nil,
            .handleSignal = &onCrash
        };
        
        [_crashReporter setCrashCallbacks:&cb];
        
        oomSupport = enableOomSupport;
        // setup out of memory support
        if(oomSupport) {
            _oomWatcher = [[OomWatcher alloc] initWithCrashReporter:_crashReporter andAttributes:_backtraceAttributes andApi:_backtraceApi];
        }
        instance = self;
        
        
    }
    
    return instance;
}

- (void) start {
    //send pending reports
    [self sendPendingReports];
    //enable crash reporter
    [_crashReporter enableCrashReporter];
    if(oomSupport){
        [self startNotificationsIntegration];
    }
}


- (void)nativeReport: (const char*) rawMessage {
    NSData *data = [_crashReporter generateLiveReport];
    NSMutableDictionary *attributes = [BacktraceAttributes getCrashAttributes];
    if(rawMessage != NULL) {
        [attributes setObject:[NSString stringWithUTF8String: rawMessage] forKey: @"error.message"];
    }
    [_backtraceApi upload:data withAttributes:attributes andCompletionHandler:^(bool shouldRemove) {
        if(!shouldRemove) {
            NSLog(@"Backtrace: Cannot upload native report");
        }
    }];
}

- (void) startNotificationsIntegration {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundNotification)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleForegroundNotification)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleTerminateNotification)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLowMemoryWarning)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    
}


- (void)handleBackgroundNotification {
    [_oomWatcher backgroundNotification];
}

- (void)handleForegroundNotification {
    [_oomWatcher foregroundNotification];
}

- (void)handleTerminateNotification {
    [OomWatcher cleanup];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleLowMemoryWarning {
    [_oomWatcher saveLowMemoryState];
}


- (void)addAttribute:(const char*)key withValue:(const char*)value {
    [_backtraceAttributes addAttribute:key withValue:value];
}

- (void) purgePendingCrashReport {
    [_crashReporter purgePendingCrashReport];
    NSString* reportPath =[Utils getDefaultReportPath];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:&error];
}

- (void) sendPendingReports {
    if(![_crashReporter hasPendingCrashReport])
    {
        return;
    }
    NSData *data = [_crashReporter loadPendingCrashReportData];
    PLCrashReport *report = [[PLCrashReport alloc] initWithData: data error: NULL];
    NSDictionary* attributes =  [_backtraceAttributes readStoredAttributes:[Utils getDefaultReportPath]];
    if (report){
        Backtrace* callbackInstance = instance;
        NSLog(@"Backtrace: Found a crash generated in last user session. Sending data to Backtrace.");
        [_backtraceApi upload:data withAttributes:attributes andCompletionHandler:^(bool shouldRemove) {
            
            if(!shouldRemove) {
                NSLog(@"Backtrace: Cannot send report to Backtrace.");
                return;
            }
            [callbackInstance purgePendingCrashReport];
        }];
    }
}
@end
