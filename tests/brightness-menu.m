#import <Cocoa/Cocoa.h>
#import "BrightnessController.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    BrightnessController *controller = [[BrightnessController alloc] init];
    NSView *view = [controller menuViewForDisplay:3 name:@"ARZOPA"];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:1];
    while(until.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    int sliders=0,buttons=0; BOOL title=NO,error=NO;
    for(NSView *v in view.subviews) {
        if([v isKindOfClass:NSSlider.class]) {sliders++; assert(![(NSSlider*)v isEnabled]);}
        else if([v isKindOfClass:NSButton.class]) {buttons++; assert([(NSButton*)v isEnabled]);}
        else if([v isKindOfClass:NSTextField.class]) {NSString *s=[(NSTextField*)v stringValue]; title|=[s containsString:@"ARZOPA"];error|=[s containsString:@"无法读取"];}
        assert(NSContainsRect(view.bounds,v.frame));
    }
    assert(sliders==1&&buttons==1&&title&&error);
    puts("PASS: inline title, slider, retry, failure state, bounds and async completion");
}}
