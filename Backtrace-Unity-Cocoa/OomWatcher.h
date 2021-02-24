#import "CrashReporter.h"
#import "BacktraceAttributes.h"
#import "BacktraceApi.h"

@interface OomWatcher : NSObject {

    // current application state
    NSMutableDictionary* _applicationState;
    
    // reporter
    PLCrashReporter* _crashReporter;

    // attributes
    BacktraceAttributes* _attributes;

    // http client instance
    BacktraceApi* _backtraceApi;
}
+ (void) cleanup;
- (instancetype)initWithCrashReporter:(PLCrashReporter*) reporter andAttributes:(BacktraceAttributes*) attributes andApi:(BacktraceApi*) api;
- (void) startOomIntegration;
- (void) sendOomReports;
- (BOOL) shouldReportOom: (NSDictionary*) state;
- (void) backgroundNotification;
- (void) foregroundNotification;
- (void) saveLowMemoryState;
@end
