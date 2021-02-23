@interface BacktraceAttributes : NSObject {

    /**
     Report attributes
     */
    NSMutableDictionary* attributes;
}
- (instancetype)initWithAttributes:(NSMutableDictionary*) attributes;
+ (NSMutableDictionary*)getCrashAttributes;
+ (NSMutableDictionary*)getAttributes;
- (void) addAttribute:(const char*)key withValue:(const char*)value;
- (NSMutableDictionary*)getUnityAttributes;
- (NSMutableDictionary*)readStoredAttributes:(NSString*) reportPath;

@end