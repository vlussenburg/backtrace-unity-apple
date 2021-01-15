#import "CrashReporter.h"
#import <mach/mach.h>
#import <Foundation/Foundation.h>

struct Entry {
    const char* key;
    const char* value;
};

@interface Backtrace_Unity_Cocoa : NSObject
+ (Backtrace_Unity_Cocoa*)create:(const char*) rawUrl withAttributes:(NSMutableDictionary*) attributes;
- (void)addAttibute:(const char*)key withValue:(const char*)value;
- (void)nativeReport:(const char*) rawMessage;
- (void) upload: (NSData*) data withAttributes:(NSDictionary*) attributes;
- (void) sendPendingReports;
+ (void) Crash;
+ (NSMutableDictionary*)getAttibutes;
@end


@implementation Backtrace_Unity_Cocoa

/**
 PL Crash reporter instance
 */
PLCrashReporter *_crashReporter;

/**
 Class instance
 */
Backtrace_Unity_Cocoa *instance;

/**
 Report attributes
 */
NSMutableDictionary *_attributes;

/**
 Backtrace URL
 */
NSURL* uploadUrl;
// Return native iOS attributes
// Attributes support doesn't require to use instance of BacktraceCrashReporter object
// we still want to provide attributes when someone doesn't want to capture native crashes
// GetAttributes function will alloc space in memory for NSDicionary and will put all attributes
// there. In Unity layer we will reuse intPtr to get all attributes from NSDictionary.
+ (NSMutableDictionary*)getAttibutes  {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    
    //read process info
    struct task_vm_info info;
    mach_msg_type_number_t systemMemorySize = TASK_VM_INFO_COUNT;
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_VM_INFO,
                                   (task_info_t)&info,
                                   &systemMemorySize);
    if( kerr == KERN_SUCCESS ) {
        [dictionary setObject:[NSString stringWithFormat:@"%0.0llu", (info.resident_size / 1048576)] forKey: @"process.vm.rss.size"];
        [dictionary setObject:[NSString stringWithFormat:@"%0.0llu", (info.virtual_size / 1048576)] forKey: @"process.vm.vma.size"];
        [dictionary setObject:[NSString stringWithFormat:@"%0.0llu", (info.resident_size_peak / 1048576)] forKey: @"process.vm.rss.peak"];
    }
    
    // read memory usage
    vm_statistics64_data_t vm_stat;
    mach_port_t host_port;
    mach_msg_type_number_t host_size;
    vm_size_t pagesize;
    
    host_port = mach_host_self();
    host_size = sizeof(vm_statistics64_data_t) / sizeof(integer_t);
    host_page_size(host_port, &pagesize);
    
    
    kern_return_t kerr2 = host_statistics64(host_port, HOST_VM_INFO64, (host_info_t)&vm_stat, &host_size);
    if ( kerr2== KERN_SUCCESS) {
        /* Stats in bytes */
        unsigned long pagesizeKb = pagesize / 1024;
        unsigned long active = vm_stat.active_count * pagesizeKb;
        [dictionary setObject: [NSString stringWithFormat:@"%0.0lu", active] forKey:@"system.memory.active"];
        
        unsigned long inactive = vm_stat.inactive_count * pagesizeKb;
        [dictionary setObject: [NSString stringWithFormat:@"%0.0lu", inactive] forKey: @"system.memory.inactive"];
        
        unsigned long free = vm_stat.free_count * pagesizeKb;
        [dictionary setObject:[NSString stringWithFormat:@"%0.0lu", free] forKey: @"system.memory.free"];
        
        unsigned long wired = vm_stat.wire_count * pagesizeKb;
        [dictionary setObject: [NSString stringWithFormat:@"%0.0lu", wired] forKey:@"system.memory.wired"];
        
        unsigned long used = active + inactive + wired;
        [dictionary setObject: [NSString stringWithFormat:@"%0.0lu", used] forKey:@"system.memory.used"];
        [dictionary setObject: [NSString stringWithFormat:@"%0.0lu", used + free] forKey:@"system.memory.total" ];
        [dictionary setObject: [NSString stringWithFormat:@"%0.0llu", vm_stat.swapins] forKey:@"system.memory.swapins" ];
        [dictionary setObject: [NSString stringWithFormat:@"%0.0llu", vm_stat.swapouts] forKey:@"system.memory.swapouts"];
    }
    return dictionary;
}
+ (Backtrace_Unity_Cocoa*)current {
    return instance;
}

+ (NSString*) getCacheDir {
    NSString *cacheDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [cacheDirectory stringByAppendingPathComponent:@"BacktraceCache"];
}

+ (NSString*) getDefaultReportPath {
    return [ [Backtrace_Unity_Cocoa getCacheDir] stringByAppendingPathComponent:@"Backtrace.plist"];
}

+ (BOOL) prepareStorage:(NSString*) backtraceDir {
    BOOL isDir = NO;
    NSError *error;
    if (! [[NSFileManager defaultManager] fileExistsAtPath:backtraceDir isDirectory:&isDir]) {
       return [[NSFileManager defaultManager]createDirectoryAtPath:backtraceDir withIntermediateDirectories:YES attributes:nil error:&error];
    } else {
       return isDir;
    }
}

static void onCrash(siginfo_t *info, ucontext_t *uap, void *context) {
    NSMutableDictionary *attributes = [[[Backtrace_Unity_Cocoa current] getUnityAttributes] mutableCopy];
    [attributes addEntriesFromDictionary:[Backtrace_Unity_Cocoa getAttibutes]];
    NSString* errorMessage = [@"siginfo_t.si_signo:" stringByAppendingString:[@(info->si_signo) stringValue]];
    [attributes setObject:errorMessage  forKey:@"error.message"];
    NSString* backtraceDir = [Backtrace_Unity_Cocoa getCacheDir];
    if([Backtrace_Unity_Cocoa prepareStorage:backtraceDir]) {
        NSString* reportPath =[backtraceDir stringByAppendingPathComponent:@"Backtrace.plist"];
        [attributes writeToFile:reportPath atomically:YES];
        NSLog(@"Stored attributes at path:%@", reportPath);
    } else {
         NSLog(@"Cannot create storage dir:%@", backtraceDir);
    }
}

+ (Backtrace_Unity_Cocoa*)create:(const char*) rawUrl withAttributes:(NSMutableDictionary*) attributes {
    if(instance != nil) {
        return instance;
    }
    
    if(!rawUrl) {
        return nil;
    }
    
    instance = [[Backtrace_Unity_Cocoa alloc] init];
    uploadUrl = [NSURL URLWithString:[NSString stringWithUTF8String: rawUrl]];
    _attributes = attributes;
    
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
    
    //send pending reports
    [instance sendPendingReports];
    //enable crash reporter
    [_crashReporter enableCrashReporter];
    
    
    return instance;
}
- (NSDictionary*)getUnityAttributes {
    return _attributes;
    
}

- (void)nativeReport: (const char*) rawMessage {
    NSData *data = [_crashReporter generateLiveReport];
    NSMutableDictionary *attributes = [[[Backtrace_Unity_Cocoa current] getUnityAttributes] mutableCopy];
    [attributes addEntriesFromDictionary:[Backtrace_Unity_Cocoa getAttibutes]];
    if(rawMessage != NULL) {
        [attributes setObject:[NSString stringWithUTF8String: rawMessage] forKey: @"error.message"];
    }
    
    [instance upload:data withAttributes:attributes];
}

- (void)addAttibute:(const char*)key withValue:(const char*)value {
    [_attributes setObject:[NSString stringWithUTF8String: value] forKey:[NSString stringWithUTF8String: key]];
}

- (void) sendPendingReports {
    if([_crashReporter hasPendingCrashReport])
    {
        NSData *data = [_crashReporter loadPendingCrashReportData];
        PLCrashReport *report = [[PLCrashReport alloc] initWithData: data error: NULL];
        NSDictionary* attributes =  [instance readStoredAttributes];
        if (report){
            [instance upload:data withAttributes:attributes];
        }
    }
}

- (NSDictionary*) readStoredAttributes {
    NSString* reportPath = [Backtrace_Unity_Cocoa getDefaultReportPath];
    if(![[NSFileManager defaultManager] fileExistsAtPath:reportPath]) {
        return [NSMutableDictionary dictionary];
    } else {
        return [NSDictionary dictionaryWithContentsOfFile:reportPath];
    }
}

- (void) upload: (NSData*) crash withAttributes:(NSDictionary*) attributes {
    NSString *boundary = [@"Boundary-" stringByAppendingString: [[NSUUID UUID] UUIDString]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: uploadUrl];
    [req setHTTPMethod: @"POST"];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [req setValue:contentType forHTTPHeaderField: @"Content-Type"];
    NSData *httpBody = [self createBodyWithBoundary:boundary parameters:attributes data:crash];
    [req setHTTPBody: httpBody];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data,
                                    NSURLResponse *response,
                                    NSError *error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
        if((long)[httpResponse statusCode] == 200) {
            [_crashReporter purgePendingCrashReport];
            NSString* reportPath =[Backtrace_Unity_Cocoa getDefaultReportPath];
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:reportPath error:&error];

        }
        
    }] resume];
}
- (NSData *)createBodyWithBoundary:(NSString *)boundary
                        parameters:(NSDictionary *)attributes
                             data:(NSData *)data {
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
    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    return httpBody;
}

+ (void)Crash {
    NSArray *array = @[];
    NSObject *o = array[1];
    NSLog(array[2] == o ? @"YES": @"NO");
}
@end


// crash reporter instance
Backtrace_Unity_Cocoa *reporter;

//bool initialized = false;
//// Initialize native crash reporter handler and set basic Unity attributes that integration will store when exception occured.
void StartBacktraceIntegration(const char* rawUrl, const char* attributeKeys[], const char* attributeValues[], const int size) {
    
    if(!rawUrl){
        return;
    }
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc]initWithCapacity:size];
    for (int index =0; index < size ; index++) {
        [attributes setObject:[NSString stringWithUTF8String: attributeValues[index]] forKey:[NSString stringWithUTF8String: attributeKeys[index]]];
    }
    reporter = [Backtrace_Unity_Cocoa create:rawUrl withAttributes: attributes];
}

// Return native iOS attributes
// Attributes support doesn't require to use instance of BacktraceCrashReporter object
// we still want to provide attributes when someone doesn't want to capture native crashes
// GetAttributes function will alloc space in memory for NSDicionary and will put all attributes
// there. In Unity layer we will reuse intPtr to get all attributes from NSDictionary.
void GetAttibutes(struct Entry** entries, int* size) {
    NSMutableDictionary* dictionary = [Backtrace_Unity_Cocoa getAttibutes];
    int count = (int) [dictionary count];
    
    *entries = malloc(count * sizeof(struct Entry));
    int index = 0;
    for(id key in dictionary) {
        (*entries)[index].key = [key UTF8String];
        
        (*entries)[index].value = [[dictionary objectForKey:key]  UTF8String];
        index += 1;
    }
    
    *size = count;
}

void NativeReport(const char* message) {
    // reporter is disabled
       if(!reporter) {
           return;
       }
    [reporter nativeReport:message];
    
}
void AddAttribute(char* key, char* value) {
    // there is no reason to store attribuets when integration is disabled
    if(!reporter) {
        return;
    }
    [reporter addAttibute:key withValue:value];
    
}
void Crash() {
    [Backtrace_Unity_Cocoa Crash];
}
