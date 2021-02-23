
@interface BacktraceApi : NSObject{
    /**
     Backtrace URL
     */
    NSURL* uploadUrl;
}
- (instancetype)initWithBacktraceUrl:(const char*) rawUrl;
- (void) upload:(const NSData*) report withAttributes:(NSDictionary*) attributes andCompletionHandler:(void (^)(bool shouldRemoveReports)) completionHandler;
@end
