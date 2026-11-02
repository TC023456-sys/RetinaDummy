// Read-only popup tests: no display transactions or preferences writes.
#define main RetinaAppMain
#import "../main.m"
#undef main
@interface RateProbe : AppDelegate
@property NSArray *physical;
@property NSDictionary *available;
@end
@implementation RateProbe
- (NSArray *)physicalDisplayIDs { return self.physical; }
- (NSArray *)hiDPIRatesForDisplay:(CGDirectDisplayID)display width:(unsigned int)width height:(unsigned int)height {
    (void)height;
    return width == kProfiles[0].logicalWidth ? self.available[@(display)] : @[];
}
- (NSDictionary *)physicalMirrorModePlan:(NSArray *)ids rate:(double)rate error:(NSString **)error {
    (void)error;
    for (NSNumber *key in ids) {
        BOOL found=NO; for (NSNumber *available in self.available[key]) if (fabs(available.doubleValue-rate)<0.6) found=YES;
        if (!found) return nil;
    }
    return @{};
}
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    RateProbe *p = [RateProbe new];
    NSPopUpButton *resolution = [NSPopUpButton new], *rates = [NSPopUpButton new];
    NSTextField *hint = [NSTextField labelWithString:@""];
    [resolution addItemWithTitle:@"preset"]; resolution.lastItem.tag = 0;
    p.settingsResolutionPopup = resolution; p.settingsRefreshPopup = rates; p.settingsRefreshHint = hint;
    p.selectedRefreshRate = 60;
    p.physical = @[@1]; p.available = @{@1:@[@165]};
    [p settingsResolutionChanged:nil];
    assert(rates.numberOfItems == 1 && [rates.selectedItem.representedObject doubleValue] == 165);
    p.physical = @[@1,@2]; p.available = @{@1:@[@60,@120,@165],@2:@[@60,@120]};
    [p settingsResolutionChanged:nil];
    assert(rates.numberOfItems == 2 && [rates.selectedItem.representedObject doubleValue] == 60);
    p.available = @{@1:@[@59.94,@120],@2:@[@60]};
    [p settingsResolutionChanged:nil];
    assert(rates.numberOfItems == 1 && fabs([rates.selectedItem.representedObject doubleValue]-59.94)<0.01);
    p.available = @{@1:@[@165],@2:@[@60]};
    [p settingsResolutionChanged:nil]; assert(!rates.enabled && !rates.selectedItem.representedObject);
    p.physical = @[]; [p settingsResolutionChanged:nil]; assert(rates.enabled && rates.numberOfItems == 7);
    p.physical = @[@1]; p.available = @{@1:@[@165]}; resolution.lastItem.tag = 1;
    [p settingsResolutionChanged:nil]; assert(!rates.enabled);
    NSPopUpButton *native=[NSPopUpButton new];
    [native addItemWithTitle:@"2048 × 1152 · 普通"];
    native.lastItem.representedObject=@{@"width":@2048,@"height":@1152,@"pixelWidth":@2048,@"pixelHeight":@1152,@"rates":@[@60,@144,@165]};
    p.nativeFormatPopup=native; p.nativeRatePopup=rates; p.selectedRefreshRate=165;
    [rates removeAllItems]; [p nativeFormatChanged:nil];
    assert(rates.numberOfItems==3 && [rates.selectedItem.representedObject doubleValue]==165);
    [native addItemWithTitle:@"1920 × 1080 · HiDPI"];
    native.lastItem.representedObject=@{@"rates":@[@165]}; [native selectItemAtIndex:1];
    [p nativeFormatChanged:nil]; assert(rates.numberOfItems==1 && [rates.selectedItem.representedObject doubleValue]==165);
    NSDictionary *normal=@{@"width":@2048,@"height":@1152,@"pixelWidth":@2048,@"pixelHeight":@1152,@"rates":@[@165]};
    NSDictionary *hidpi=@{@"width":@1920,@"height":@1080,@"pixelWidth":@3840,@"pixelHeight":@2160,@"rates":@[@165]};
    NSDictionary *small=@{@"width":@800,@"height":@600,@"pixelWidth":@800,@"pixelHeight":@600,@"rates":@[@60]};
    [p populateNativeFormats:@[hidpi,normal,small] inPopup:native currentMode:NULL];
    assert(native.numberOfItems==6);
    assert([native.itemArray[0].title isEqual:@"普通"] && !native.itemArray[0].enabled);
    assert([native.itemArray[1].representedObject isEqual:small]);
    assert([native.itemArray[2].representedObject isEqual:normal]);
    assert(native.itemArray[3].separatorItem);
    assert([native.itemArray[4].title isEqual:@"HiDPI"] && !native.itemArray[4].enabled);
    assert([native.itemArray[5].representedObject isEqual:hidpi]);
    assert([native.selectedItem.representedObject isEqual:small]);
    [p populateNativeFormats:@[hidpi] inPopup:native currentMode:NULL];
    assert(native.numberOfItems==2 && [native.itemArray[0].title isEqual:@"HiDPI"]);
    [p populateNativeFormats:@[] inPopup:native currentMode:NULL]; assert(native.numberOfItems==0);
    p.virtualMirrorEnabled=YES; p.physical=@[@1]; p.available=@{@1:@[]};
    [p settingsResolutionChanged:nil]; assert(!rates.enabled); // A virtual source cannot override hardware timing support.
    p.available=@{@1:@[@60,@165]};
    [p settingsResolutionChanged:nil]; assert(rates.enabled && rates.numberOfItems==2);
    if (NSClassFromString(@"CGVirtualDisplayMode")) {
        assert([p virtualModesForProfile:[p currentProfile] rate:60].count==2);
        p.physical=@[];
        assert([p virtualModesForProfile:[p currentProfile] rate:60].count==7);
    }
    puts("PASS: physical rates, multi-display intersection, fractional rates, unavailable size, virtual fallback.");
} }
