@interface BacktraceAttributes : NSObject {

    /**
     Report attributes
     */
    NSMutableDictionary* _clientAttributes;
}
- (instancetype)initWithAttributes:(NSMutableDictionary*) attributes;
+ (NSMutableDictionary*)getCrashAttributes;
+ (NSMutableDictionary*)getBuiltInAttributes;
- (void) addAttribute:(const char*)key withValue:(const char*)value;
- (NSMutableDictionary*)getUnityAttributes;
- (NSMutableDictionary*)readStoredAttributes:(NSString*) reportPath;

@end
