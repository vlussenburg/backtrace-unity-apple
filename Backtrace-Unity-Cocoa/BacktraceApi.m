#import <Foundation/Foundation.h>
#import "BacktraceApi.h"

@implementation BacktraceApi

void (^_completionHandler)(int someParameter);

/**
 Backtrace URL
 */
NSURL* _uploadUrl;


// Creates Backtrace API instance - class responsible for sending native reports to Backtrace
- (instancetype)initWithBacktraceUrl:(const char*) rawUrl {
    if( self = [super init]) {
        _uploadUrl = [NSURL URLWithString:[NSString stringWithUTF8String: rawUrl]];
    }
    return self;
}

// Send report to Backtrace
- (void) upload:(NSData*) crash withAttributes:(NSDictionary*) attributes andAttachments:
(NSMutableArray*) attachmentsPaths andCompletionHandler:(void (^)(bool shouldRemoveReports)) completionHandler {
    NSString *boundary = [@"Boundary-" stringByAppendingString: [[NSUUID UUID] UUIDString]];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: _uploadUrl];
    [req setHTTPMethod: @"POST"];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [req setValue:contentType forHTTPHeaderField: @"Content-Type"];
    NSData *httpBody = [self createBodyWithBoundary:boundary parameters:attributes data:crash andAttachments:attachmentsPaths];
    [req setHTTPBody: httpBody];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data,
                                    NSURLResponse *response,
                                    NSError *error) {
        _completionHandler = [completionHandler copy];
        _completionHandler((long)[(NSHTTPURLResponse *) response statusCode] == 200);
        _completionHandler = nil;
        
    }] resume];
}

- (NSData *)createBodyWithBoundary:(NSString *)boundary
                        parameters:(NSDictionary *)attributes
                              data:(NSData *)data
                    andAttachments:(NSMutableArray*)attachmentsPaths {
    NSMutableData *httpBody = [NSMutableData data];
    
    // add params (all params are strings)
    [attributes enumerateKeysAndObjectsUsingBlock:^(NSString *parameterKey, NSString *parameterValue, BOOL *stop) {
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", parameterKey] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"%@\r\n", parameterValue] dataUsingEncoding:NSUTF8StringEncoding]];
    }];
    
    
    [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: application/octet-stream\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:data];
    [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // add attachments if it's safe to read them
    if(attachmentsPaths != nil) {
        NSFileManager* manager = [NSFileManager defaultManager];
        for (NSString* attachmentPath in attachmentsPaths) {
            if(![manager fileExistsAtPath:attachmentPath]) {
                continue;
            }
            NSString* fileName = [attachmentPath lastPathComponent];
            [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fileName, fileName] dataUsingEncoding:NSUTF8StringEncoding]];
            [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: application/octet-stream\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            [httpBody appendData:[NSData dataWithContentsOfFile:attachmentPath]];
            [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    return httpBody;
}

@end
