//
//  Backtrace_Unity_Cocoa.h
//  Backtrace-Unity-Cocoa
//
//  Created by Backtrace on 11/3/20.
//  Copyright © 2020 Backtrace. All rights reserved.
//

#import <Foundation/Foundation.h>

struct Entry {
    const char* key;
    const char* value;
};

@interface Backtrace_Unity_Cocoa : NSObject
+ (Backtrace_Unity_Cocoa*)create:(const char*) rawUrl withAttributeKeys:(const char*)attributeKeys withAttributeValues:(const char*)attributeValues withSize:(const int)size;
- (void)addAttibute:(const char*)key withValue:(const char*)value;
- (void) upload: (NSData*) data;
- (void) sendPendingReports;
+ (void) HandleAnr;
+ (void) Crash;
+ (void)getAttibutes:(struct Entry**)entries forSize:(int*) size;
@end
