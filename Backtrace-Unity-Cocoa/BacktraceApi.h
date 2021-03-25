
@interface BacktraceApi : NSObject{
    /**
     Backtrace URL
     */
    NSURL* _uploadUrl;
}
- (instancetype)initWithBacktraceUrl:(const char*) rawUrl;
- (void) upload:(NSData*) crash withAttributes:(NSDictionary*) attributes andAttachments:
(NSMutableArray*) attachmentsPaths andCompletionHandler:(void (^)(bool shouldRemoveReports)) completionHandler;
@end
