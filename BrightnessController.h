#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
@interface BrightnessController : NSWindowController
- (void)showForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name;
@end
