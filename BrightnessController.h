#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
@interface BrightnessController : NSWindowController
- (NSView *)menuViewForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name;
- (void)showForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name;
@end
