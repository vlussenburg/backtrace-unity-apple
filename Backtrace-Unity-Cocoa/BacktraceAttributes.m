#import <Foundation/Foundation.h>
#import "BacktraceAttributes.h"
#import <mach/mach.h>

@implementation BacktraceAttributes

/**
 Backtrace attributes require to use singleton instance to store/save attributes
 when crash occured.
 */
static BacktraceAttributes* instance;

/**
 stored Unity attributes
 */
NSMutableDictionary* _clientAttributes;

/**
 Return native iOS attributes
 Attributes support doesn't require to use instance of BacktraceCrashReporter object
 we still want to provide attributes when someone doesn't want to capture native crashes
 GetAttributes function will alloc space in memory for NSDicionary and will put all attributes
 there. In Unity layer we will reuse intPtr to get all attributes from NSDictionary.
 */
+ (NSMutableDictionary*)getBuiltInAttributes  {
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


+ (NSMutableDictionary *)getCrashAttributes {
    BacktraceAttributes* attributesInstance = instance;
    if(attributesInstance == nil) {
        return [BacktraceAttributes getBuiltInAttributes];
    }
    NSMutableDictionary* attr = [[attributesInstance getUnityAttributes] mutableCopy];
    [attr addEntriesFromDictionary:[BacktraceAttributes getBuiltInAttributes]];
    return attr;
    
}

- (instancetype)initWithAttributes:(NSMutableDictionary *)attributes {
    if(instance != nil) {
        return instance;
    }
    if( self = [super init]) {
        // https://stackoverflow.com/a/38963835/4818730
        [attributes setObject: @"0" forKey:@"thread.main"];
        _clientAttributes = attributes;
        instance = self;
    }
    return instance;
}


- (NSDictionary*)getUnityAttributes {
    return _clientAttributes;
}

- (void)addAttribute:(const char*)key withValue:(const char*)value {
    NSString* keyString = key != NULL ? [NSString stringWithUTF8String: key] : @"";
    if(!keyString) {
        keyString = @"";
    }
    NSString* valueString = value != NULL ? [NSString stringWithUTF8String: value] : @"";
    if(!valueString) {
        valueString = @"";
    }
    [_clientAttributes setObject: valueString forKey: keyString];
}


- (NSDictionary*) readStoredAttributes:(NSString*) reportPath {
    if([[NSFileManager defaultManager] fileExistsAtPath:reportPath]) {
        NSDictionary* result = [NSDictionary dictionaryWithContentsOfFile:reportPath];
        if(result) {
            return result;
        }
    }
    return [NSMutableDictionary dictionary];
}

@end
