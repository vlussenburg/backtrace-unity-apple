#import "CrashReporter.h"
#import "BacktraceApi.h"
#import "Utils.h"
#import "OomWatcher.h"

@interface Backtrace : NSObject {
    PLCrashReporter* _crashReporter;
    BacktraceApi* _backtraceApi;
    BacktraceAttributes* _backtraceAttributes;
    OomWatcher* _oomWatcher;
    bool oomSupport;
}
- (instancetype)initWithBacktraceUrl:(const char*) rawUrl andAttributes:(NSMutableDictionary*) attributes andOomSupport:(bool) enableOomSupport;
- (void) start;
- (void) addAttribute:(const char*)key withValue:(const char*)value;
- (void) nativeReport:(const char*) rawMessage;
- (void) sendPendingReports;
@end


struct Entry {
    const char* key;
    const char* value;
};
