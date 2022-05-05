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
 Attachment paths
 */
NSMutableArray* _attachmentsPaths;
/**
 Class instance
 */
static Backtrace *instance;

bool oomSupport;

bool disabled;

static void onCrash(siginfo_t *info, ucontext_t *uap, void *context) {
    [OomWatcher cleanup];
    NSMutableDictionary *attributes = [BacktraceAttributes getCrashAttributes];
    
    NSString* errorMessage = [@"siginfo_t.si_signo:" stringByAppendingString:[@(info->si_signo) stringValue]];
    [attributes setObject:errorMessage  forKey:@"error.message"];
    [attributes setObject:[instance getAttachments] forKey:@"__attachment_storage"];
    NSString* reportPath =[Utils getDefaultReportPath];
    [attributes writeToFile:reportPath atomically:YES];
    NSLog(@"Backtrace: Received game crash. Storing attributes at path:%@", reportPath);
}

- (instancetype)initWithBacktraceUrl:(const char*) rawUrl andAttributes:(NSMutableDictionary*) attributes andOomSupport:(bool) enableOomSupport andAttachments:(NSMutableArray*) attachments andClientSideUnwinding:(bool) clientSideUnwinding {
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
        _attachmentsPaths = attachments;
        
        // initialize Crash reporter
        PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeBSD;
        PLCrashReporterSymbolicationStrategy symbolicationStrategy = (clientSideUnwinding)
            ? PLCrashReporterSymbolicationStrategyAll
            : PLCrashReporterSymbolicationStrategyNone;
        
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
        if(oomSupport) {
            _oomWatcher = [[OomWatcher alloc] initWithCrashReporter:_crashReporter andAttributes:_backtraceAttributes andApi:_backtraceApi andAttachments:attachments];
        }
    
        instance = self;
        disabled = NO;
        
    }
    
    return instance;
}

- (void) start {
    //send pending reports
    [self sendPendingReports];
    //enable crash reporter
    NSError* error;
    [_crashReporter enableCrashReporterAndReturnError:&error];
    if(error) {
        NSLog(@"Backtrace: Cannot initialize crash reporter. Reason: %@ %@", error, [error userInfo]);
        return;
    }
    if(oomSupport){
        [self startNotificationsIntegration];
    }
}

- (NSMutableArray*) getAttachments {
    return _attachmentsPaths;
}

- (void)nativeReport: (const char*) rawMessage withMainThreadAsFaultingThread:(bool) setMainThreadAsFaultingThread {
    NSError* error;
    NSData *data = [_crashReporter generateLiveReportAndReturnError:&error];
    if(error) {
        NSLog(@"Backtrace: Cannot create a native report. Reason: %@ %@", error, [error userInfo]);
        return;
    }
    NSMutableDictionary *attributes = [BacktraceAttributes getCrashAttributes];
    if(rawMessage != NULL) {
        [attributes setObject:[NSString stringWithUTF8String: rawMessage] forKey: @"error.message"];
    }
    if(setMainThreadAsFaultingThread == true) {
        [attributes setObject:@"0" forKey: @"_mod_faulting_tid"];
    }
    NSMutableArray* attachments=  [self getAttachments];
    [_backtraceApi upload:data withAttributes:attributes andAttachments:attachments andCompletionHandler:^(bool shouldRemove) {
        if(!shouldRemove) {
            NSLog(@"Backtrace: Cannot upload native report.");
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
                                             selector:@selector(disableIntegration)
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

- (void)disableIntegration {
    if(disabled == YES){
        return;
    }
    [OomWatcher cleanup];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(oomSupport){
        [_oomWatcher disable];
    }
    disabled = YES;
    NSLog(@"Backtrace: Backtrace native integration has been disabled.");
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
    NSError *error = nil;
    NSData *data = [_crashReporter loadPendingCrashReportDataAndReturnError:&error];
    if(error) {
        NSLog(@"Backtrace: Cannot load pending crash reports. Reason: %@ %@", error, [error userInfo]);
        [_crashReporter purgePendingCrashReport];
    }
    if(!data) {
        return;
    }
    
    PLCrashReport *report = [[PLCrashReport alloc] initWithData: data error:&error];
    if(error) {
        NSLog(@"Backtrace: Cannot initialize a new report from the old application session. Reason: %@ %@", error, [error userInfo]);
        [_crashReporter purgePendingCrashReport];
        return;
    }
    NSMutableDictionary* attributes =  [_backtraceAttributes readStoredAttributes:[Utils getDefaultReportPath]];
    if (report){
        NSMutableArray* attachments = [[self getAttachments] mutableCopy];
        if(attributes != nil && [attributes objectForKey:@"__attachment_storage"] != nil) {
            NSMutableArray* prevAttachments = [attributes objectForKey:@"__attachment_storage"];
            for (NSString* storedAttachment in prevAttachments)
            {
                // make sure you don't add it if it's already there.
                [attachments removeObject:storedAttachment];
                [attachments addObject:storedAttachment];
            }
            [attributes removeObjectForKey:@"__attachment_storage"];
        }
        Backtrace* callbackInstance = instance;
        NSLog(@"Backtrace: Found a crash generated in last user session. Sending data to Backtrace.");
        [_backtraceApi upload:data withAttributes:attributes andAttachments:attachments andCompletionHandler:^(bool shouldRemove) {
            
            if(!shouldRemove) {
                NSLog(@"Backtrace: Cannot send report to Backtrace.");
                return;
            }
            [callbackInstance purgePendingCrashReport];
        }];
    }
}
@end
