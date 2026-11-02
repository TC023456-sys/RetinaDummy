#define main RetinaAppMain
#import "../main.m"
#undef main
#include <assert.h>

// All display enumeration/configuration and confirmation methods used by this
// test are replaced below. Never start the app or call a real display backend.
@interface AppDelegate (HiddenNativePickerTestContract)
- (NSArray<NSDictionary *> *)publicNativeFormatsForDisplay:(CGDirectDisplayID)display;
- (NSArray<NSDictionary *> *)hiddenNativeFormatsForDisplay:(CGDirectDisplayID)display;
- (void)applyPhysicalFormat:(NSDictionary *)format physical:(NSArray<NSNumber *> *)physical rate:(double)rate;
- (NSDictionary *)hiddenNativePlanForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight
    rate:(double)rate error:(NSString **)error;
- (BOOL)applyHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error;
- (BOOL)hiddenNativePlanIsCurrent:(NSDictionary *)plan error:(NSString **)error;
- (BOOL)restoreHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error;
@end

static NSDictionary *Format(NSUInteger w,NSUInteger h,NSUInteger pw,NSUInteger ph,NSArray *rates) {
    return @{@"width":@(w),@"height":@(h),@"pixelWidth":@(pw),@"pixelHeight":@(ph),@"rates":rates};
}
static NSDictionary *FindFormat(NSArray *formats,NSUInteger w,NSUInteger h,NSUInteger pw,NSUInteger ph) {
    NSDictionary *found=nil;
    for(NSDictionary *format in formats) {
        if([format[@"width"] unsignedIntegerValue]==w&&[format[@"height"] unsignedIntegerValue]==h
           &&[format[@"pixelWidth"] unsignedIntegerValue]==pw&&[format[@"pixelHeight"] unsignedIntegerValue]==ph) {
            assert(!found);found=format;
        }
    }
    return found;
}
static NSUInteger CountRate(NSDictionary *format,double wanted) {
    NSUInteger count=0;for(NSNumber *rate in format[@"rates"])if(fabs(rate.doubleValue-wanted)<0.01)count++;
    return count;
}

// Only the two selectors used by the saved-selection method are needed. These
// plain objects avoid creating AppKit controls or connecting a test to a screen.
@interface SavedPopupItem : NSObject
@property NSDictionary *representedObject;
@end
@implementation SavedPopupItem
@end
@interface SavedPopupProbe : NSObject
@property NSArray<SavedPopupItem *> *itemArray;
@property SavedPopupItem *selectedItem;
- (void)selectItem:(SavedPopupItem *)item;
@end
@implementation SavedPopupProbe
- (void)selectItem:(SavedPopupItem *)item { self.selectedItem=item; }
@end
static SavedPopupItem *PopupItem(NSDictionary *format) {
    SavedPopupItem *item=[SavedPopupItem new];item.representedObject=format;return item;
}

@interface HiddenPickerProbe : AppDelegate
@property NSArray<NSNumber *> *physicalIDs;
@property NSDictionary<NSNumber *,NSArray *> *publicFormats;
@property NSDictionary<NSNumber *,NSArray *> *hiddenFormats;
@property NSUInteger hiddenEnumerations;
@property BOOL publicPlanAvailable;
@property BOOL publicApplySucceeds;
@property BOOL planFails;
@property BOOL applyFails;
@property BOOL restoreFails;
@property BOOL keep;
@property BOOL currentTarget;
@property BOOL driftTargetAtConfirmation;
@property BOOL driftTopologyAtConfirmation;
@property BOOL changeGenerationAtConfirmation;
@property NSUInteger hiddenPlans;
@property NSUInteger hiddenApplies;
@property NSUInteger hiddenVerifications;
@property NSUInteger hiddenRestores;
@property NSUInteger confirmations;
@property NSUInteger saves;
@property NSUInteger publicApplies;
@property NSUInteger reconciliations;
@property NSDictionary *lastPlan;
@property NSDictionary *originalFreshMode;
@property NSDictionary *lastPublicRequest;
@property NSString *lastError;
@end

@implementation HiddenPickerProbe
- (instancetype)init {
    if((self=[super init])) {
        self.physicalIDs=@[@2];self.displayManagementEnabled=YES;
        self.preferPhysicalDisplays=YES;self.selectedDisplayCount=1;
        self.selectedProfile=2;self.customLogicalWidth=2000;self.customLogicalHeight=1200;
        self.selectedRefreshRate=60;self.physicalPixelWidth=3840;self.physicalPixelHeight=2160;
        self.displays=[NSMutableArray array];self.mirrorOriginals=[NSMutableDictionary dictionary];
        self.keep=YES;self.publicApplySucceeds=YES;
        self.originalFreshMode=RDNMRequestInfo((RDNativeModeRequest){1920,1080,3840,2160,60});
        self.publicFormats=@{
            @2:@[Format(1920,1080,1920,1080,@[@60,@165]),Format(2048,1152,4096,2304,@[@60]),Format(1920,1080,3840,2160,@[@60])],
            @3:@[Format(1920,1080,1920,1080,@[@165]),Format(2048,1152,4096,2304,@[@60]),Format(1920,1080,3840,2160,@[@60])]
        };
        self.hiddenFormats=@{
            @2:@[Format(1600,900,3200,1800,@[@165,@165]),Format(1920,1080,3840,2160,@[@60,@165,@165]),Format(2560,1440,5120,2880,@[@165])],
            @3:@[Format(1600,900,3200,1800,@[@165])]
        };
    }
    return self;
}
- (NSArray *)physicalDisplayIDs { return self.physicalIDs; }
- (NSArray *)IDsForVirtualDisplays:(NSArray *)displays { return displays?:@[]; }
- (NSArray *)publicNativeFormatsForDisplay:(CGDirectDisplayID)display { return self.publicFormats[@(display)]?:@[]; }
- (NSArray *)hiddenNativeFormatsForDisplay:(CGDirectDisplayID)display {
    self.hiddenEnumerations++;return self.hiddenFormats[@(display)]?:@[];
}
- (BOOL)topologyMatchesPhysical:(NSArray *)physical virtualIDs:(NSArray *)virtualIDs {
    return [[NSSet setWithArray:physical] isEqualToSet:[NSSet setWithArray:self.physicalIDs]]
        &&[[self IDsForVirtualDisplays:self.displays] isEqual:virtualIDs];
}
- (NSDictionary *)modePlanForDisplays:(NSArray *)ids width:(unsigned int)width height:(unsigned int)height rate:(double)rate error:(NSString **)error {
    (void)width;(void)height;(void)rate;
    if(!self.publicPlanAvailable){if(error)*error=@"mock: no public exact mode";return nil;}
    NSMutableDictionary *plan=[NSMutableDictionary dictionary];for(NSNumber *display in ids)plan[display]=@"mock-public-mode";return plan;
}
- (void)applyUnifiedSettingsProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate {
    self.publicApplies++;
    self.lastPublicRequest=@{@"profile":@(profile),@"width":@(width),@"height":@(height),@"pixelWidth":@(self.physicalPixelWidth),@"pixelHeight":@(self.physicalPixelHeight),@"rate":@(rate)};
    self.lastSettingsApplyKept=self.publicApplySucceeds;
}
- (NSDictionary *)hiddenNativePlanForDisplays:(NSArray *)ids width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight rate:(double)rate error:(NSString **)error {
    self.hiddenPlans++;
    if(self.planFails){if(error)*error=@"mock: hidden preflight refused";return nil;}
    self.lastPlan=@{@"entries":@[@{@"displayID":ids[0],@"identity":@{@"uuid":@"00000000-0000-0000-0000-000000000002",@"location":@"mock-only"},
        @"before":self.originalFreshMode}],
        @"request":RDNMRequestInfo((RDNativeModeRequest){width,height,pixelWidth,pixelHeight,rate})};
    return self.lastPlan;
}
- (BOOL)applyHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error {
    assert(self.applyingDisplaySettings&&[plan isEqual:self.lastPlan]);self.hiddenApplies++;
    if(self.applyFails){if(error)*error=@"mock: apply failed; backend owns recovery";return NO;}
    self.currentTarget=YES;return YES;
}
- (BOOL)hiddenNativePlanIsCurrent:(NSDictionary *)plan error:(NSString **)error {
    assert([plan isEqual:self.lastPlan]);self.hiddenVerifications++;
    if(!self.currentTarget&&error)*error=@"mock: target changed";return self.currentTarget;
}
- (BOOL)restoreHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error {
    assert(self.applyingDisplaySettings&&[plan isEqual:self.lastPlan]);self.hiddenRestores++;
    assert([plan[@"entries"][0][@"before"] isEqual:self.originalFreshMode]);
    if(self.restoreFails){if(error)*error=@"mock: restore refused unknown/external state";return NO;}
    self.currentTarget=NO;return YES;
}
- (BOOL)confirmUnifiedDisplaySettings {
    assert(self.applyingDisplaySettings);self.confirmations++;
    // Requested preferences may only be published after keep + fresh checks.
    assert(self.selectedProfile==2&&self.customLogicalWidth==2000&&self.customLogicalHeight==1200);
    assert(self.selectedRefreshRate==60&&self.physicalPixelWidth==3840&&self.physicalPixelHeight==2160&&self.saves==0);
    if(self.driftTargetAtConfirmation)self.currentTarget=NO;
    if(self.driftTopologyAtConfirmation)self.physicalIDs=@[@3];
    if(self.changeGenerationAtConfirmation)self.displayChangeGeneration++;
    return self.keep;
}
- (void)persistUnifiedSettings { self.saves++; }
- (void)rebuildMenu {}
- (void)showError:(NSString *)error { self.lastError=error; }
- (void)scheduleDisplayReconciliation { self.reconciliations++; }
@end

static void ApplyHidden(HiddenPickerProbe *probe) {
    [probe applyPhysicalFormat:Format(1600,900,3200,1800,@[@165]) physical:@[@2] rate:165];
}
static void OriginalPreferences(HiddenPickerProbe *probe) {
    assert(probe.selectedProfile==2&&probe.customLogicalWidth==2000&&probe.customLogicalHeight==1200);
    assert(probe.selectedRefreshRate==60&&probe.physicalPixelWidth==3840&&probe.physicalPixelHeight==2160);
}

int main(void) { @autoreleasepool {
    assert(!RDLogicalSizeMatchesDesktop(800,600,NSMakeSize(2048,1152),0));
    assert(RDLogicalSizeMatchesDesktop(2048,1152,NSMakeSize(2048,1152),0));
    assert(RDLogicalSizeMatchesDesktop(2048,1152,NSMakeSize(1152,2048),90));
    HiddenPickerProbe *saved=[HiddenPickerProbe new];
    saved.selectedProfile=kProfileCount;saved.customLogicalWidth=2048;saved.customLogicalHeight=1152;
    saved.physicalPixelWidth=4096;saved.physicalPixelHeight=2304;
    SavedPopupItem *small=PopupItem(Format(800,600,1600,1200,@[@165]));
    SavedPopupItem *normal=PopupItem(Format(2048,1152,2048,1152,@[@165]));
    SavedPopupItem *hidpi=PopupItem(Format(2048,1152,4096,2304,@[@165]));
    SavedPopupProbe *popup=[SavedPopupProbe new];popup.itemArray=@[small,normal,hidpi];
    assert([saved selectSavedNativeFormatInPopup:(NSPopUpButton *)(id)popup desktopSize:NSMakeSize(2048,1152) rotation:0]);
    assert(popup.selectedItem==hidpi&&popup.selectedItem!=small&&popup.selectedItem!=normal);
    popup.selectedItem=nil;
    assert(![saved selectSavedNativeFormatInPopup:(NSPopUpButton *)(id)popup desktopSize:NSMakeSize(1920,1080) rotation:0]);
    assert(!popup.selectedItem); // Do not present a mismatched saved setting as current.
    assert([saved selectSavedNativeFormatInPopup:(NSPopUpButton *)(id)popup desktopSize:NSMakeSize(1152,2048) rotation:90]);
    assert(popup.selectedItem==hidpi);
    HiddenPickerProbe *p=[HiddenPickerProbe new];NSArray *formats=[p nativeFormatsForDisplays:@[@2]];
    assert(p.hiddenEnumerations==1);
    assert(CountRate(FindFormat(formats,1600,900,3200,1800),165)==1);
    assert(CountRate(FindFormat(formats,1920,1080,3840,2160),165)==1);
    assert(CountRate(FindFormat(formats,2560,1440,5120,2880),165)==1);
    assert(CountRate(FindFormat(formats,1920,1080,3840,2160),60)==1);
    assert(CountRate(FindFormat(formats,1920,1080,1920,1080),165)==1); // Keep the distinct LoDPI row.
    p=[HiddenPickerProbe new];p.physicalIDs=@[@2,@3];formats=[p nativeFormatsForDisplays:p.physicalIDs];
    assert(p.hiddenEnumerations==0&&!FindFormat(formats,1600,900,3200,1800));
    assert(CountRate(FindFormat(formats,1920,1080,1920,1080),165)==1);
    assert(CountRate(FindFormat(formats,1920,1080,1920,1080),60)==0);
    assert(CountRate(FindFormat(formats,1920,1080,3840,2160),165)==0);
    for(NSUInteger variant=0;variant<3;variant++) {
        p=[HiddenPickerProbe new];if(variant==0)p.displays=[@[@100] mutableCopy];
        if(variant==1)p.virtualMirrorEnabled=YES;if(variant==2)p.mirroredPhysicalDisplay=2;
        formats=[p nativeFormatsForDisplays:@[@2]];
        assert(p.hiddenEnumerations==0&&!FindFormat(formats,1600,900,3200,1800));
        assert(FindFormat(formats,1920,1080,1920,1080));
    }
    p=[HiddenPickerProbe new];ApplyHidden(p);
    assert(p.hiddenPlans==1&&p.hiddenApplies==1&&p.hiddenVerifications>=1&&p.confirmations==1&&p.hiddenRestores==0&&p.saves==1&&p.publicApplies==0);
    assert(p.lastSettingsApplyKept&&p.unifiedSettingsEnabled&&!p.suspendSavedSettings&&!p.applyingDisplaySettings);
    assert(p.customLogicalWidth==1600&&p.customLogicalHeight==900&&p.physicalPixelWidth==3200&&p.physicalPixelHeight==1800&&p.selectedRefreshRate==165);
    p=[HiddenPickerProbe new];p.keep=NO;ApplyHidden(p); // Same result as the confirmation timeout.
    assert(p.hiddenApplies==1&&p.hiddenRestores==1&&p.saves==0&&!p.lastSettingsApplyKept&&p.suspendSavedSettings&&!p.applyingDisplaySettings);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.keep=NO;p.restoreFails=YES;ApplyHidden(p);
    assert(p.hiddenRestores==1&&p.saves==0&&!p.lastSettingsApplyKept&&p.suspendSavedSettings&&p.lastError.length);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.applyFails=YES;ApplyHidden(p);
    assert(p.hiddenApplies==1&&p.hiddenRestores==0&&p.confirmations==0&&p.saves==0&&p.suspendSavedSettings);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.planFails=YES;ApplyHidden(p);
    assert(p.hiddenPlans==1&&p.hiddenApplies==0&&p.hiddenRestores==0&&p.saves==0);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.driftTargetAtConfirmation=YES;p.restoreFails=YES;ApplyHidden(p);
    assert(p.saves==0&&!p.lastSettingsApplyKept&&p.suspendSavedSettings&&p.hiddenRestores<=1);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.driftTopologyAtConfirmation=YES;p.restoreFails=YES;ApplyHidden(p);
    assert(p.saves==0&&!p.lastSettingsApplyKept&&p.suspendSavedSettings&&p.hiddenRestores<=1);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.changeGenerationAtConfirmation=YES;ApplyHidden(p);
    assert(p.saves==0&&p.hiddenRestores==0&&!p.lastSettingsApplyKept&&!p.suspendSavedSettings);OriginalPreferences(p);
    for(NSUInteger variant=0;variant<8;variant++) {
        p=[HiddenPickerProbe new];NSArray *physical=@[@2];
        if(variant==0){p.physicalIDs=@[@2,@3];physical=p.physicalIDs;}
        if(variant==1)p.displays=[@[@100] mutableCopy];
        if(variant==2)p.virtualMirrorEnabled=YES;
        if(variant==3)p.mirroredPhysicalDisplay=2;
        if(variant==4)p.mirrorOriginals[@2]=@{};
        if(variant==5)p.selectedDisplayCount=2;
        if(variant==6)p.preferPhysicalDisplays=NO;
        if(variant==7)p.displayManagementEnabled=NO;
        [p applyPhysicalFormat:Format(1600,900,3200,1800,@[@165]) physical:physical rate:165];
        assert(p.hiddenApplies==0&&p.hiddenPlans==0&&p.saves==0);OriginalPreferences(p);
    }
    p=[HiddenPickerProbe new];[p applyPhysicalFormat:Format(1600,900,1600,900,@[@165]) physical:@[@2] rate:165];
    assert(p.hiddenPlans==0&&p.hiddenApplies==0&&p.saves==0);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.publicPlanAvailable=YES;
    p.originalFreshMode=RDNMRequestInfo((RDNativeModeRequest){2048,1152,4096,2304,165});
    [p applyPhysicalFormat:Format(1920,1080,1920,1080,@[@165]) physical:@[@2] rate:165];
    assert(p.publicApplies==0&&p.hiddenPlans==1&&p.hiddenApplies==1&&p.confirmations==1&&p.hiddenVerifications>=1&&p.saves==1&&p.hiddenRestores==0);
    assert(p.lastSettingsApplyKept&&p.physicalPixelWidth==1920&&p.physicalPixelHeight==1080&&p.selectedRefreshRate==165);
    assert([p.lastPlan[@"entries"][0][@"before"] isEqual:p.originalFreshMode]);
    p=[HiddenPickerProbe new];p.publicPlanAvailable=YES;p.keep=NO;
    // The safe cancel must receive this fresh2048 snapshot, never a cached800
    // record or the ordinary1920 target that is being rejected.
    p.originalFreshMode=RDNMRequestInfo((RDNativeModeRequest){2048,1152,4096,2304,165});
    [p applyPhysicalFormat:Format(1920,1080,1920,1080,@[@165]) physical:@[@2] rate:165];
    assert(p.publicApplies==0&&p.hiddenPlans==1&&p.hiddenApplies==1&&p.hiddenRestores==1&&p.saves==0&&!p.lastSettingsApplyKept&&p.suspendSavedSettings);
    assert([p.lastPlan[@"entries"][0][@"before"][@"width"] unsignedIntValue]==2048);OriginalPreferences(p);
    p=[HiddenPickerProbe new];p.publicPlanAvailable=YES;p.physicalIDs=@[@2,@3];p.selectedDisplayCount=2;
    [p applyPhysicalFormat:Format(1920,1080,1920,1080,@[@165]) physical:p.physicalIDs rate:165];
    assert(p.publicApplies==1&&p.hiddenPlans==0&&p.hiddenApplies==0);
    assert([p.lastPublicRequest[@"pixelWidth"] unsignedIntValue]==1920&&[p.lastPublicRequest[@"rate"] doubleValue]==165);
    puts("PASS: hidden native picker merge/intersection, bounds-consistent saved HiDPI selection and rotation; distinct LoDPI, deduplicated165Hz, safe single-physical routing, keep-only preference save, cancel/timeout recovery, drift and failed-apply no extra rollback; pure mocks only.");
    return 0;
} }
