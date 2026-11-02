#import <Cocoa/Cocoa.h>
#import "BrightnessController.h"
@interface QuietBrightnessController : BrightnessController
@end
@implementation QuietBrightnessController
- (void)refreshClicked:(id)sender { (void)sender; } // UI-state test, no helper/hardware.
@end
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
    // Regression: old menus and their items may remain alive while a fresh
    // menu is built. Never attach the same cached NSView to both items.
    NSMenu *oldMenu=[NSMenu new], *newMenu=[NSMenu new];
    NSMenuItem *oldItem=[NSMenuItem new], *newItem=[NSMenuItem new];
    oldItem.view=view; [oldMenu addItem:oldItem];
    NSView *replacement=[controller menuViewForDisplay:3 name:@"ARZOPA"];
    assert(replacement!=view && replacement.subviews.count==4);
    assert(replacement.frame.size.height<=110);
    newItem.view=replacement; [newMenu addItem:newItem];
    [oldMenu removeAllItems]; oldItem=nil; oldMenu=nil;
    assert(newItem.view==replacement && replacement.subviews.count==4);
    for(NSView *v in replacement.subviews) assert(NSContainsRect(replacement.bounds,v.frame));
    QuietBrightnessController *success=[QuietBrightnessController new];
    [success menuViewForDisplay:3 name:@"ARZOPA"];
    NSSlider *windowSlider=[success valueForKey:@"slider"];
    windowSlider.doubleValue=64; windowSlider.enabled=YES;
    [(NSTextField *)[success valueForKey:@"status"] setStringValue:@"硬件亮度：64% · 已读取确认"];
    NSView *successView=[success menuViewForDisplay:3 name:@"ARZOPA"];
    BOOL successSlider=NO,successText=NO;
    for (NSView *v in successView.subviews) {
        if ([v isKindOfClass:NSSlider.class]) successSlider=[(NSSlider *)v isEnabled] && [(NSSlider *)v doubleValue]==64;
        if ([v isKindOfClass:NSTextField.class]) successText |= [[(NSTextField *)v stringValue] containsString:@"64%"];
    }
    assert(successSlider && successText);
    puts("PASS: inline controls, async failure state, compact bounds, independent views across menu rebuilds");
}}
