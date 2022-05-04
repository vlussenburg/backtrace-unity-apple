#import "CrashReporter.h"
#import "BacktraceApi.h"
#import "Utils.h"
#import "OomWatcher.h"

@interface Backtrace : NSObject {
    PLCrashReporter* _crashReporter;
    BacktraceApi* _backtraceApi;
    BacktraceAttributes* _backtraceAttributes;
    OomWatcher* _oomWatcher;
    NSMutableArray* _attachmentsPaths;
    bool oomSupport;
    bool disabled;
}
- (instancetype)initWithBacktraceUrl:(const char*) rawUrl andAttributes:(NSMutableDictionary*) attributes andOomSupport:(bool) enableOomSupport andAttachments:(NSMutableArray*) attachments andClientSideUnwinding:(bool) clientSideUnwinding;
- (void) start;
- (void) addAttribute:(const char*)key withValue:(const char*)value;
- (void) nativeReport:(const char*) rawMessage withMainThreadAsFaultingThread:(bool) setMainThreadAsFaultingThread;
- (void) sendPendingReports;
- (void)disableIntegration;
@end


struct Entry {
    const char* key;
    const char* value;
};
