
#import <Foundation/Foundation.h>
#import "Backtrace.h"
#import "Utils.h"

/**
 Entry point for Backtrace Unity calls
 */


// crash reporter instance
Backtrace *reporter;

bool debugMode;
//// Initialize native crash reporter handler and set basic Unity attributes that integration will store when exception occured.
void StartBacktraceIntegration(const char* rawUrl, const char* attributeKeys[], const char* attributeValues[], const int size, bool enableOomSupport, const char* attachments[], const int attachmentSize, bool enableClientSideUnwinding) {
    
    if(!rawUrl){
        return;
    }
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc]initWithCapacity:size];
    for (int index =0; index < size ; index++) {
        NSString* attributeKey = attributeKeys[index] != NULL ? [NSString stringWithUTF8String: attributeKeys[index]] : @"";
        
        if(attributeKey == NULL) {
            NSLog(@"Backtrace: Cannot store attribute key: %s", attributeKeys[index]);
            attributeKey = @"";
        }
        
        NSString* attributeValue = attributeValues[index] != NULL ? [NSString stringWithUTF8String: attributeValues[index]] : @"";
        if(attributeValue == NULL) {
            NSLog(@"Backtrace: Cannot store attribute value: %s", attributeValues[index]);
            attributeValue = @"";
        }
        [attributes setObject:attributeValue forKey:attributeKey];
    }
    
    NSMutableArray* attachmentPaths = [[NSMutableArray alloc] initWithCapacity:attachmentSize];
    for (int index =0; index< attachmentSize; index++) {
        if(attachments[index] != NULL) {
            [attachmentPaths addObject:[NSString stringWithUTF8String: attachments[index]]];
        }
    }
    debugMode = [Utils isDebuggerAttached];
    reporter = [[Backtrace alloc] initWithBacktraceUrl:rawUrl andAttributes: attributes andOomSupport:enableOomSupport andAttachments:attachmentPaths andClientSideUnwinding:enableClientSideUnwinding];
    if(reporter){
        [reporter start];
    }
}

// Return native iOS attributes
// Attributes support doesn't require to use instance of BacktraceCrashReporter object
// we still want to provide attributes when someone doesn't want to capture native crashes
// GetAttributes function will alloc space in memory for NSDicionary and will put all attributes
// there. In Unity layer we will reuse intPtr to get all attributes from NSDictionary.
void GetAttributes(struct Entry** entries, int* size) {
    NSMutableDictionary* dictionary = [BacktraceAttributes getBuiltInAttributes];
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

void NativeReport(const char* message, bool setMainThreadAsFaultingThread, bool ignoreIfDebugger) {
    // reporter is disabled
    if(!reporter) {
        return;
    }
    if(ignoreIfDebugger && debugMode) {
        NSLog(@"Backtrace: Ignoring report generated in the debug mode.");
        return;
    }
    [reporter nativeReport:message withMainThreadAsFaultingThread:setMainThreadAsFaultingThread];
    
}
void AddAttribute(char* key, char* value) {
    // there is no reason to store attribuets when integration is disabled
    if(!reporter) {
        return;
    }
    [reporter addAttribute:key withValue:value];
    
}
void Crash(void) {
    [Utils crash];
}

void Disable(void) {
    [reporter disableIntegration];
}
