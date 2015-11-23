#import <Cordova/CDV.h>

@interface WebviewCacheManager : CDVPlugin

- (void)clearBrowserCache:(CDVInvokedUrlCommand *)command;
- (void)clearAppCacheByUrl:(CDVInvokedUrlCommand *)command;
- (void)clearAllAppCache:(CDVInvokedUrlCommand *)command;
- (void)clearCookies:(CDVInvokedUrlCommand *)command;

@end
