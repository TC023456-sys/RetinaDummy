#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>
#import <objc/runtime.h>
#import <math.h>
#import <dlfcn.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#import "UpdateCheck.h"
#import "BrightnessController.h"
#import "DisplayModePolicy.h"
#import "NativeDisplayModes.h"

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic, copy) void (^terminationHandler)(void);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, copy) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@end

typedef struct {
    const char *key;
    const char *title;
    unsigned int width;
    unsigned int height;
    unsigned int logicalWidth;
    unsigned int logicalHeight;
    BOOL hiDPI;
} DisplayProfile;

static const DisplayProfile kProfiles[] = {
    {"1280x720", "1280 × 720 HiDPI", 2560, 1440, 1280, 720, YES},
    {"1600x900", "1600 × 900 HiDPI", 3200, 1800, 1600, 900, YES},
    {"1920x1080", "1920 × 1080 HiDPI", 3840, 2160, 1920, 1080, YES},
    {"2048x1152", "2048 × 1152 HiDPI", 4096, 2304, 2048, 1152, YES},
    {"2560x1440", "2560 × 1440 HiDPI（推荐）", 5120, 2880, 2560, 1440, YES},
    {"3008x1692", "3008 × 1692 HiDPI", 6016, 3384, 3008, 1692, YES},
    {"3072x1728", "3072 × 1728 HiDPI", 6144, 3456, 3072, 1728, YES},
    {"3200x1800", "3200 × 1800 HiDPI", 6400, 3600, 3200, 1800, YES},
    {"3440x1440", "3440 × 1440 HiDPI（超宽）", 6880, 2880, 3440, 1440, YES},
    {"3840x2160", "3840 × 2160 HiDPI（高性能占用）", 7680, 4320, 3840, 2160, YES},
    {"ipad-mini-8.3", "iPad mini 8.3″  ·  2266 × 1488", 4532, 2976, 2266, 1488, YES},
    {"ipad-11", "iPad 11″ / Air 11″  ·  2360 × 1640", 4720, 3280, 2360, 1640, YES},
    {"ipad-pro-11", "iPad Pro 11″  ·  2420 × 1668", 4840, 3336, 2420, 1668, YES},
    {"ipad-air-13", "iPad Air 13″  ·  2732 × 2048", 5464, 4096, 2732, 2048, YES},
    {"ipad-pro-13", "iPad Pro 13″  ·  2752 × 2064", 5504, 4128, 2752, 2064, YES},
};
static const NSUInteger kDesktopProfileCount = 10;
static const NSUInteger kProfileCount = sizeof(kProfiles) / sizeof(kProfiles[0]);

static BOOL RuntimeSupportsVirtualDisplays(NSString **error) {
    NSDictionary<NSString *, NSArray<NSString *> *> *shape = @{
        @"CGVirtualDisplayDescriptor": @[@"init", @"setName:", @"setMaxPixelsWide:", @"setMaxPixelsHigh:", @"setSizeInMillimeters:", @"setVendorID:", @"setProductID:", @"setSerialNum:", @"setQueue:"],
        @"CGVirtualDisplay": @[@"initWithDescriptor:", @"applySettings:", @"displayID"],
        @"CGVirtualDisplaySettings": @[@"init", @"setModes:", @"setHiDPI:"],
        @"CGVirtualDisplayMode": @[@"initWithWidth:height:refreshRate:"]
    };
    for (NSString *className in shape) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            if (error) *error = [NSString stringWithFormat:@"系统缺少 %@", className];
            return NO;
        }
        for (NSString *selectorName in shape[className]) {
            if (!class_getInstanceMethod(cls, NSSelectorFromString(selectorName))) {
                if (error) *error = [NSString stringWithFormat:@"系统不支持 %@.%@", className, selectorName];
                return NO;
            }
        }
    }
    return YES;
}

// Mirrored physical displays may be absent from NSScreen.screens. Resolve
// their hardware name separately, with a fallback if this private API changes.
static NSString *PhysicalDisplayName(CGDirectDisplayID displayID) {
    static CFDictionaryRef (*copyInfo)(CGDirectDisplayID);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY);
        if (library) copyInfo = dlsym(library, "CoreDisplay_DisplayCreateInfoDictionary");
    });
    NSDictionary *info = copyInfo ? CFBridgingRelease(copyInfo(displayID)) : nil;
    id names = info[@"DisplayProductName"];
    if ([names isKindOfClass:NSDictionary.class]) {
        id name = names[NSLocale.currentLocale.localeIdentifier] ?: names[@"en_US"] ?: [names allValues].firstObject;
        if ([name isKindOfClass:NSString.class]) return name;
    } else if ([names isKindOfClass:NSString.class]) return names;
    return [NSString stringWithFormat:@"显示器 %u", displayID];
}

static NSTextField *MakeLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.alignment = NSTextAlignmentCenter;
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMutableArray<CGVirtualDisplay *> *displays;
@property(nonatomic) NSUInteger selectedProfile;
@property(nonatomic) NSUInteger selectedDisplayCount;
@property(nonatomic) BOOL preferPhysicalDisplays;
@property(nonatomic) BOOL displayManagementEnabled;
@property(nonatomic) NSUInteger displayChangeGeneration;
@property(nonatomic) unsigned int customLogicalWidth;
@property(nonatomic) unsigned int customLogicalHeight;
@property(nonatomic) double selectedRefreshRate;
@property(nonatomic, strong) NSWindow *aboutWindow;
@property(nonatomic) CGDirectDisplayID mirroredPhysicalDisplay;
@property(nonatomic) CGDirectDisplayID previousMirror;
@property(nonatomic) BOOL checkingUpdate;
@property(nonatomic) BOOL manualUpdateRequested;
@property(nonatomic, strong) NSTimer *updateTimer;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *,BrightnessController *> *brightnessControllers;
@property(nonatomic) BOOL unifiedSettingsEnabled;
@property(nonatomic) BOOL applyingDisplaySettings;
@property(nonatomic, copy) NSString *displaySettingsIssue;
@property(nonatomic, copy) NSString *failedSettingsSignature;
@property(nonatomic, copy) NSString *failedVirtualCreationSignature;
@property(nonatomic) BOOL suspendSavedSettings;
@property(nonatomic) BOOL reconcilingDisplays;
@property(nonatomic) BOOL displayReconciliationPending;
@property(nonatomic, weak) NSPopUpButton *settingsResolutionPopup;
@property(nonatomic, weak) NSPopUpButton *settingsRefreshPopup;
@property(nonatomic, weak) NSTextField *settingsRefreshHint;
@property(nonatomic, weak) NSTextField *settingsCustomWidth;
@property(nonatomic, weak) NSTextField *settingsCustomHeight;
@property(nonatomic, weak) NSPopUpButton *nativeFormatPopup;
@property(nonatomic, weak) NSPopUpButton *nativeRatePopup;
@property(nonatomic, weak) NSButton *nativeApplyButton;
@property(nonatomic) unsigned int physicalPixelWidth;
@property(nonatomic) unsigned int physicalPixelHeight;
@property(nonatomic) BOOL lastSettingsApplyKept;
@property(nonatomic) BOOL virtualMirrorEnabled;
@property(nonatomic) BOOL mirrorConfigurationConfirmed;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *mirrorOriginals;
- (void)applyVirtualMirrorProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate confirm:(BOOL)confirm;
- (BOOL)restoreVirtualMirrorTargets;
- (BOOL)automaticUpdateChecksEnabled;
- (void)checkAutomatically:(id)sender;
- (void)beginUpdateCheckManual:(BOOL)manual;
- (DisplayProfile)currentProfile;
- (void)restartDisplaysIfActive;
- (void)showResolutionPicker:(id)sender;
- (void)showCustomResolutionAtRate:(double)rate;
- (void)restoreLoginItemIfRequested;
- (NSUInteger)physicalDisplayCount;
- (NSMutableArray<CGVirtualDisplay *> *)createVirtualDisplays:(NSUInteger)desired;
- (void)scheduleDisplayReconciliation;
- (void)flushPendingDisplayReconciliation;
- (void)enqueueDisplayReconciliationAfter:(NSTimeInterval)delay generation:(NSUInteger)generation;
- (void)performDisplayReconciliationForGeneration:(NSUInteger)generation;
- (NSArray<NSNumber *> *)physicalDisplayIDs;
- (void)applyUnifiedSettingsProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate;
- (void)applySavedSettingsToActiveDisplays;
- (NSArray<NSDictionary *> *)publicNativeFormatsForDisplay:(CGDirectDisplayID)display;
- (NSArray<NSDictionary *> *)hiddenNativeFormatsForDisplay:(CGDirectDisplayID)display;
- (void)applyPhysicalFormat:(NSDictionary *)format physical:(NSArray<NSNumber *> *)physical rate:(double)rate;
- (BOOL)selectSavedNativeFormatInPopup:(NSPopUpButton *)popup desktopSize:(NSSize)desktop rotation:(double)rotation;
- (NSDictionary *)hiddenNativePlanForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight
    rate:(double)rate error:(NSString **)error;
- (BOOL)applyHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error;
- (BOOL)hiddenNativePlanIsCurrent:(NSDictionary *)plan error:(NSString **)error;
- (BOOL)restoreHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error;
- (BOOL)restoreHiddenNativeModesForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight
    rate:(double)rate error:(NSString **)error;
@end

static void RetinaDisplayChanged(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *context) {
    (void)display;
    if (flags & kCGDisplayBeginConfigurationFlag) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [(__bridge AppDelegate *)context scheduleDisplayReconciliation];
    });
}

static NSUInteger RDDesiredVirtualCount(NSUInteger requested,BOOL preferPhysical,NSUInteger physicalCount) {
    return preferPhysical ? (physicalCount>=requested ? 0 : requested-physicalCount) : requested;
}

static BOOL RDLogicalSizeMatchesDesktop(NSUInteger width,NSUInteger height,NSSize desktop,double rotation) {
    if (!width || !height || !isfinite(desktop.width) || !isfinite(desktop.height) || !isfinite(rotation)) return NO;
    BOOL direct=fabs(desktop.width-width)<0.5 && fabs(desktop.height-height)<0.5;
    double angle=fmod(fmod(rotation,360)+360,360);
    BOOL quarterTurn=fabs(angle-90)<0.01 || fabs(angle-270)<0.01;
    return direct || (quarterTurn && fabs(desktop.width-height)<0.5 && fabs(desktop.height-width)<0.5);
}

@implementation AppDelegate
@synthesize applyingDisplaySettings = _applyingDisplaySettings;
@synthesize reconcilingDisplays = _reconcilingDisplays;

- (void)setApplyingDisplaySettings:(BOOL)applying {
    _applyingDisplaySettings = applying;
    if (!applying) [self flushPendingDisplayReconciliation];
}

- (void)setReconcilingDisplays:(BOOL)reconciling {
    _reconcilingDisplays = reconciling;
    if (!reconciling) [self flushPendingDisplayReconciliation];
}

- (void)flushPendingDisplayReconciliation {
    if (!self.displayReconciliationPending || self.applyingDisplaySettings || self.reconcilingDisplays) return;
    self.displayReconciliationPending = NO;
    if (self.displayManagementEnabled) [self scheduleDisplayReconciliation];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"profile"] ?: @"2560x1440";
    self.selectedProfile = 4;
    for (NSUInteger i = 0; i < kProfileCount; i++) {
        if ([saved isEqualToString:@(kProfiles[i].key)]) self.selectedProfile = i;
    }
    self.customLogicalWidth = (unsigned int)[[NSUserDefaults standardUserDefaults] integerForKey:@"customLogicalWidth"];
    self.customLogicalHeight = (unsigned int)[[NSUserDefaults standardUserDefaults] integerForKey:@"customLogicalHeight"];
    if (self.customLogicalWidth < 640) self.customLogicalWidth = 2000;
    if (self.customLogicalHeight < 480) self.customLogicalHeight = 1979;
    if ([saved isEqualToString:@"custom-hidpi"]) self.selectedProfile = kProfileCount;
    NSInteger savedCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"displayCount"];
    self.selectedDisplayCount = (NSUInteger)MAX(1, MIN(3, savedCount ?: 1));
    NSUserDefaults *settings = NSUserDefaults.standardUserDefaults;
    self.preferPhysicalDisplays = [settings objectForKey:@"preferPhysicalDisplays"] == nil || [settings boolForKey:@"preferPhysicalDisplays"];
    self.displayManagementEnabled = YES;
    // Old virtual-only preferences are not silently applied to hardware on upgrade.
    self.unifiedSettingsEnabled = [settings boolForKey:@"unifiedDisplaySettingsEnabled"];
    self.virtualMirrorEnabled = [settings objectForKey:@"virtualMirrorEnabled"] == nil || [settings boolForKey:@"virtualMirrorEnabled"];
    self.mirrorConfigurationConfirmed = [settings boolForKey:@"mirrorConfigurationConfirmed"];
    // An in-place UI-only update can restart the app while the user's live
    // display differs from saved settings. Consume this installer flag once;
    // an explicit Apply still clears suspendSavedSettings as usual.
    if ([settings boolForKey:@"preserveCurrentDisplayModesOnce"]) {
        self.suspendSavedSettings=YES;
        [settings removeObjectForKey:@"preserveCurrentDisplayModesOnce"];
    }
    self.physicalPixelWidth = (unsigned int)MAX(0, [settings integerForKey:@"physicalPixelWidth"]);
    self.physicalPixelHeight = (unsigned int)MAX(0, [settings integerForKey:@"physicalPixelHeight"]);
    double savedRefreshRate = [[NSUserDefaults standardUserDefaults] doubleForKey:@"refreshRate"];
    self.selectedRefreshRate = isfinite(savedRefreshRate) && savedRefreshRate >= 1 && savedRefreshRate <= 1000 ? savedRefreshRate : 60;

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Retina Dummy"];
    self.statusItem.button.toolTip = @"Retina Dummy 虚拟显示器";
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--enable-login-item"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"launchAtLoginRequested"];
    }
    [self restoreLoginItemIfRequested];
    [self rebuildMenu];
    CGDisplayRegisterReconfigurationCallback(RetinaDisplayChanged, (__bridge void *)self);
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(displayWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [self startDisplay:nil];
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:3600 target:self selector:@selector(checkAutomatically:) userInfo:nil repeats:YES];
    self.updateTimer.tolerance = 60;
    [self checkAutomatically:nil];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    [self rebuildMenu];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    (void)sender; (void)visible;
    if (NSApp.modalWindow) [NSApp.modalWindow makeKeyAndOrderFront:nil];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self showResolutionPicker:nil]; });
    return NO;
}

- (void)rebuildMenu {
    // Update the menu AppKit is about to display in place. Replacing the
    // status menu and transferring custom-view items during tracking can
    // detach their view hierarchy while retaining the row's reserved height.
    NSMenu *menu = self.statusItem.menu ?: [[NSMenu alloc] init];
    [menu removeAllItems];
    menu.delegate = self;
    BOOL active = self.displays.count > 0;
    NSString *headerTitle = active
        ? [NSString stringWithFormat:@"%lu 个虚拟显示器已开启", (unsigned long)self.displays.count]
        : @"虚拟显示器已关闭";
    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:headerTitle action:nil keyEquivalent:@""];
    if (self.preferPhysicalDisplays && self.displayManagementEnabled) {
        header.title = [NSString stringWithFormat:@"目标 %lu 屏 · 实体 %lu · 虚拟 %lu", (unsigned long)self.selectedDisplayCount, (unsigned long)[self physicalDisplayCount], (unsigned long)self.displays.count];
    }
    header.enabled = NO;
    if (self.virtualMirrorEnabled) header.title = [NSString stringWithFormat:@"虚拟高清 · 实体 %lu · 虚拟 %lu",(unsigned long)[self physicalDisplayCount],(unsigned long)self.displays.count];
    [menu addItem:header];
    [menu addItem:[NSMenuItem separatorItem]];

    uint32_t count = 0; CGDirectDisplayID ids[64];
    CGGetOnlineDisplayList(64, ids, &count);
    if (!self.brightnessControllers) self.brightnessControllers = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *connectedBrightnessDisplays = [NSMutableSet set];
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID displayID = ids[i];
        if (!RDIsPhysicalDisplay(CGDisplayVendorNumber(displayID), CGDisplayModelNumber(displayID))) continue;
        NSString *name = PhysicalDisplayName(displayID);
        for (NSScreen *screen in NSScreen.screens) {
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == displayID) name = screen.localizedName;
        }
        if (!CGDisplayIsBuiltin(displayID)) {
            NSNumber *key = @(displayID);
            [connectedBrightnessDisplays addObject:key];
            BrightnessController *controller = self.brightnessControllers[key];
            if (!controller) {
                controller = [[BrightnessController alloc] init];
                self.brightnessControllers[key] = controller;
            }
            NSMenuItem *inlineBrightness = [[NSMenuItem alloc] initWithTitle:[name stringByAppendingString:@" 亮度"] action:nil keyEquivalent:@""];
            inlineBrightness.view = [controller menuViewForDisplay:displayID name:name];
            [menu addItem:inlineBrightness];
            [menu addItem:[NSMenuItem separatorItem]];
        }
    }
    for (NSNumber *key in self.brightnessControllers.allKeys) {
        if (![connectedBrightnessDisplays containsObject:key]) [self.brightnessControllers removeObjectForKey:key];
    }
    if (self.mirroredPhysicalDisplay) {
        NSMenuItem *restore = [[NSMenuItem alloc] initWithTitle:@"恢复原来的镜像设置" action:@selector(restorePhysicalDisplay:) keyEquivalent:@""];
        restore.target = self; [menu addItem:restore];
    }
    DisplayProfile currentProfile = [self currentProfile];
    NSMenuItem *resolutionItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"统一显示设置…   %u × %u @ %.0fHz%@", currentProfile.logicalWidth, currentProfile.logicalHeight, self.selectedRefreshRate, self.unifiedSettingsEnabled ? @"" : @"（待应用）"]
               action:@selector(showResolutionPicker:)
        keyEquivalent:@""];
    resolutionItem.target = self;
    [menu addItem:resolutionItem];
    if (self.displaySettingsIssue.length) {
        NSMenuItem *issue = [[NSMenuItem alloc] initWithTitle:@"查看显示状态…" action:@selector(showDisplaySettingsIssue:) keyEquivalent:@""];
        issue.target = self; [menu addItem:issue];
    }
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *priority = [[NSMenuItem alloc] initWithTitle:@"实体屏优先，按总屏幕数补足" action:@selector(togglePhysicalPriority:) keyEquivalent:@""];
    priority.target = self;
    priority.state = self.preferPhysicalDisplays ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.virtualMirrorEnabled) { priority.title=@"虚拟高清画面 → 实体屏幕"; priority.action=nil; priority.enabled=NO; priority.state=NSControlStateValueOff; }
    [menu addItem:priority];
    NSString *countTitle = self.preferPhysicalDisplays && !self.virtualMirrorEnabled ? @"目标屏幕总数" : @"虚拟显示器数量";
    NSMenuItem *countItem = [[NSMenuItem alloc] initWithTitle:countTitle action:nil keyEquivalent:@""];
    NSMenu *countMenu = [[NSMenu alloc] initWithTitle:@"虚拟显示器数量"];
    for (NSUInteger count = 1; count <= 3; count++) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithFormat:(self.preferPhysicalDisplays && !self.virtualMirrorEnabled ? @"总共 %lu 个屏幕" : @"%lu 个虚拟显示器"), (unsigned long)count]
                   action:@selector(selectDisplayCount:)
            keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)count;
        item.state = (count == self.selectedDisplayCount ? NSControlStateValueOn : NSControlStateValueOff);
        [countMenu addItem:item];
    }
    countItem.submenu = countMenu;
    [menu addItem:countItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSString *toggleTitle = self.preferPhysicalDisplays
        ? (self.displayManagementEnabled ? @"暂停自动屏幕管理" : @"启用自动屏幕管理")
        : (active ? @"关闭虚拟显示器" : @"开启虚拟显示器");
    BOOL canStop = self.preferPhysicalDisplays ? self.displayManagementEnabled : active;
    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:toggleTitle action:(canStop ? @selector(stopDisplay:) : @selector(startDisplay:)) keyEquivalent:@""];
    toggle.target = self;
    [menu addItem:toggle];
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"登录时自动启动" action:@selector(toggleLoginItem:) keyEquivalent:@""];
    login.target = self;
    login.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff);
    [menu addItem:login];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *update = [[NSMenuItem alloc] initWithTitle:(self.checkingUpdate ? @"正在检查更新…" : @"检查更新…") action:@selector(checkForUpdates:) keyEquivalent:@""];
    update.target = self; update.enabled = !self.checkingUpdate; [menu addItem:update];
    NSMenuItem *automatic = [[NSMenuItem alloc] initWithTitle:@"自动检查更新（每天一次）" action:@selector(toggleAutomaticUpdateChecks:) keyEquivalent:@""];
    automatic.target = self;
    automatic.state = [self automaticUpdateChecksEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:automatic];
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"关于 Retina Dummy" action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [menu addItem:about];
    NSMenuItem *diagnostics = [[NSMenuItem alloc] initWithTitle:@"复制诊断信息" action:@selector(copyDiagnostics:) keyEquivalent:@""];
    diagnostics.target = self;
    [menu addItem:diagnostics];
    NSMenuItem *uninstall = [[NSMenuItem alloc] initWithTitle:@"卸载说明…" action:@selector(showUninstallHelp:) keyEquivalent:@""];
    uninstall.target = self;
    [menu addItem:uninstall];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Retina Dummy" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)showDisplaySettingsIssue:(id)sender {
    (void)sender;
    if (!self.displaySettingsIssue.length) return;
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"显示状态";
    alert.informativeText=self.displaySettingsIssue;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

- (BOOL)automaticUpdateChecksEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:@"automaticUpdateChecks"] ? [defaults boolForKey:@"automaticUpdateChecks"] : YES;
}

- (void)toggleAutomaticUpdateChecks:(id)sender {
    (void)sender;
    [NSUserDefaults.standardUserDefaults setBool:![self automaticUpdateChecksEnabled] forKey:@"automaticUpdateChecks"];
    [self rebuildMenu];
    [self checkAutomatically:nil];
}

- (void)checkAutomatically:(id)sender {
    (void)sender;
    NSTimeInterval last = [NSUserDefaults.standardUserDefaults doubleForKey:@"lastSuccessfulUpdateCheck"];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval attempted = [NSUserDefaults.standardUserDefaults doubleForKey:@"lastAutomaticUpdateAttempt"];
    if (!self.checkingUpdate && RetinaAutomaticUpdateDue([self automaticUpdateChecksEnabled], last, attempted, now)) {
        [NSUserDefaults.standardUserDefaults setDouble:now forKey:@"lastAutomaticUpdateAttempt"];
        [self beginUpdateCheckManual:NO];
    }
}

- (void)checkForUpdates:(id)sender {
    (void)sender;
    [self beginUpdateCheckManual:YES];
}

- (void)beginUpdateCheckManual:(BOOL)manual {
    if (self.applyingDisplaySettings) return;
    if (manual) self.manualUpdateRequested = YES;
    if (self.checkingUpdate) return;
    self.checkingUpdate = YES; [self rebuildMenu];
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/TC023456-sys/RetinaDummy/releases?per_page=100"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"RetinaDummy-UpdateCheck" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        id releases = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *latest = RetinaLatestRelease(releases);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL requestedManually = self.manualUpdateRequested;
            self.manualUpdateRequested = NO;
            self.checkingUpdate = NO; [self rebuildMenu];
            if (self.applyingDisplaySettings) return; // Do not nest an updater alert over timed rollback.
            if (error || http.statusCode != 200 || !latest) {
                if (requestedManually) [self showError:@"检查更新失败，请稍后重试。也可访问 GitHub Releases 下载新版。"];
                return;
            }
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            [defaults setDouble:NSDate.date.timeIntervalSince1970 forKey:@"lastSuccessfulUpdateCheck"];
            if (!requestedManually && ![self automaticUpdateChecksEnabled]) return;
            NSString *version = latest[@"version"];
            NSString *current = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
            if ([version compare:current options:NSNumericSearch] != NSOrderedDescending) {
                if (requestedManually) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"已是最新版本";
                    alert.informativeText = [NSString stringWithFormat:@"当前版本：%@\n更新来源：TC023456-sys/RetinaDummy", current];
                    [alert addButtonWithTitle:@"好"]; [NSApp activateIgnoringOtherApps:YES]; [alert runModal];
                }
                return;
            }
            if (!requestedManually && [[defaults stringForKey:@"lastNotifiedUpdateVersion"] isEqual:version]) return;
            [defaults setObject:version forKey:@"lastNotifiedUpdateVersion"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"发现新版本 %@", version];
            alert.informativeText = @"更新来源：TC023456-sys/RetinaDummy\n下载后退出 Retina Dummy，解压并替换“应用程序”中的旧版本，再重新打开。";
            [alert addButtonWithTitle:@"下载新版"]; [alert addButtonWithTitle:@"稍后"];
            [NSApp activateIgnoringOtherApps:YES];
            if ([alert runModal] == NSAlertFirstButtonReturn) [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:latest[@"download"]]];
        });
    }] resume];
}

- (void)showAbout:(id)sender {
    (void)sender;
    if (self.aboutWindow) {
        [self.aboutWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }

    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"未知";
    NSString *build = info[@"CFBundleVersion"] ?: @"未知";

    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"关于 Retina Dummy";
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;
    window.backgroundColor = NSColor.windowBackgroundColor;
    [window center];

    NSView *content = window.contentView;
    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = MakeLabel(@"Retina Dummy", 26, NSFontWeightSemibold, NSColor.labelColor);
    NSTextField *versionLabel = MakeLabel(
        [NSString stringWithFormat:@"版本 %@ · 构建 %@", version, build],
        13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSTextField *summary = MakeLabel(
        @"为无实体显示器的 Mac 创建\n清晰、流畅的 HiDPI 虚拟屏幕。",
        15, NSFontWeightRegular, NSColor.labelColor);

    NSVisualEffectView *notice = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    notice.material = NSVisualEffectMaterialContentBackground;
    notice.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    notice.state = NSVisualEffectStateActive;
    notice.wantsLayer = YES;
    notice.layer.cornerRadius = 10;
    notice.layer.masksToBounds = YES;
    notice.layer.backgroundColor = [NSColor.separatorColor colorWithAlphaComponent:0.08].CGColor;
    notice.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.28].CGColor;
    notice.layer.borderWidth = 0.5;
    notice.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *noticeTitle = MakeLabel(@"兼容性说明", 13, NSFontWeightSemibold, NSColor.labelColor);
    noticeTitle.alignment = NSTextAlignmentLeft;
    NSTextField *noticeBody = MakeLabel(
        @"使用 macOS 非公开 CoreGraphics 接口。\n系统升级后可能需要更新适配。",
        13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    noticeBody.alignment = NSTextAlignmentLeft;
    [notice addSubview:noticeTitle];
    [notice addSubview:noticeBody];

    NSTextField *copyright = MakeLabel(
        @"Copyright © 2026 Retina Dummy contributors  ·  MIT License",
        11, NSFontWeightRegular, NSColor.tertiaryLabelColor);

    for (NSView *view in @[icon, title, versionLabel, summary, notice, copyright]) {
        [content addSubview:view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:34],
        [icon.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:84],
        [icon.heightAnchor constraintEqualToConstant:84],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
        [title.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [versionLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
        [versionLabel.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],

        [summary.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:22],
        [summary.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [summary.widthAnchor constraintEqualToConstant:390],

        [notice.topAnchor constraintEqualToAnchor:summary.bottomAnchor constant:22],
        [notice.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [notice.widthAnchor constraintEqualToConstant:400],
        [notice.heightAnchor constraintEqualToConstant:78],
        [noticeTitle.leadingAnchor constraintEqualToAnchor:notice.leadingAnchor constant:16],
        [noticeTitle.trailingAnchor constraintEqualToAnchor:notice.trailingAnchor constant:-16],
        [noticeTitle.topAnchor constraintEqualToAnchor:notice.topAnchor constant:12],
        [noticeBody.leadingAnchor constraintEqualToAnchor:notice.leadingAnchor constant:16],
        [noticeBody.trailingAnchor constraintEqualToAnchor:notice.trailingAnchor constant:-16],
        [noticeBody.topAnchor constraintEqualToAnchor:noticeTitle.bottomAnchor constant:5],

        [copyright.topAnchor constraintEqualToAnchor:notice.bottomAnchor constant:22],
        [copyright.centerXAnchor constraintEqualToAnchor:content.centerXAnchor]
    ]];

    self.aboutWindow = window;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)copyDiagnostics:(id)sender {
    (void)sender;
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    DisplayProfile profile = [self currentProfile];
    NSString *text = [NSString stringWithFormat:
        @"Retina Dummy %@ (%@)\nmacOS %ld.%ld.%ld\nLogical resolution: %u x %u\nRender resolution: %u x %u\nRefresh rate: %.0f Hz\nRequested displays: %lu\nActive displays: %lu\nBundle: %@",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?",
        (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion,
        profile.logicalWidth, profile.logicalHeight, profile.width, profile.height, self.selectedRefreshRate,
        (unsigned long)self.selectedDisplayCount,
        (unsigned long)self.displays.count,
        NSBundle.mainBundle.bundleIdentifier ?: @"?"];
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)showUninstallHelp:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"卸载 Retina Dummy";
    alert.informativeText = @"先取消“登录时自动启动”，然后退出应用，再将 Retina Dummy.app 移到废纸篓。\n\n如需同时清除设置，删除 ~/Library/Preferences/local.liang.RetinaDummy.plist。";
    [alert addButtonWithTitle:@"知道了"];
    [alert runModal];
}

- (void)toggleLoginItem:(NSMenuItem *)sender {
    NSError *error = nil;
    if (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) {
        [SMAppService.mainAppService unregisterAndReturnError:&error];
        if (!error) [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"launchAtLoginRequested"];
    } else {
        [SMAppService.mainAppService registerAndReturnError:&error];
        if (!error) [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"launchAtLoginRequested"];
    }
    if (error) {
        [self showError:[NSString stringWithFormat:@"无法修改登录项：%@\n请先把应用放入“应用程序”文件夹。", error.localizedDescription]];
    }
    sender.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff);
}

- (void)restoreLoginItemIfRequested {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"launchAtLoginRequested"]) return;
    if (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) return;
    NSError *error = nil;
    [SMAppService.mainAppService registerAndReturnError:&error];
    if (error) NSLog(@"Unable to restore login item: %@", error.localizedDescription);
}

- (void)selectProfile:(NSMenuItem *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= kProfileCount) return;
    [self applyUnifiedSettingsProfile:(NSUInteger)sender.tag width:self.customLogicalWidth height:self.customLogicalHeight rate:self.selectedRefreshRate];
}

- (void)showResolutionPicker:(id)sender {
    (void)sender;
    NSArray *physical = [self physicalDisplayIDs];
    if (!physical) { [self showError:@"无法读取当前显示器，未更改设置。"]; return; }
    if (physical.count && !self.virtualMirrorEnabled) { [self showPhysicalResolutionPicker:physical]; return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"统一显示设置";
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    alert.informativeText = [NSString stringWithFormat:@"当前使用：虚拟屏幕 · %@\n以下为本应用虚拟屏可配置的 2× HiDPI 格式。切换后 15 秒内确认，否则恢复。", PhysicalDisplayName(mainDisplay)];
    if (self.virtualMirrorEnabled) alert.informativeText=@"虚拟屏提供 HiDPI 画面，实体屏同步刷新率。切换后 15 秒内确认，否则恢复。";
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"取消"];

    NSView *settingsView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 76)];
    NSTextField *resolutionLabel = [NSTextField labelWithString:@"分辨率"];
    resolutionLabel.frame = NSMakeRect(0, 48, 62, 24);
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(68, 44, 332, 30) pullsDown:NO];
    [popup removeAllItems];
    NSMenuItem *desktopHeader = [popup.menu addItemWithTitle:@"— 桌面分辨率 —" action:nil keyEquivalent:@""];
    desktopHeader.enabled = NO;
    for (NSUInteger i = 0; i < kDesktopProfileCount; i++) {
        NSMenuItem *item = [popup.menu addItemWithTitle:@(kProfiles[i].title) action:nil keyEquivalent:@""];
        item.tag = (NSInteger)i;
    }
    [popup.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *iPadHeader = [popup.menu addItemWithTitle:@"— iPad 横屏尺寸 —" action:nil keyEquivalent:@""];
    iPadHeader.enabled = NO;
    for (NSUInteger i = kDesktopProfileCount; i < kProfileCount; i++) {
        NSMenuItem *item = [popup.menu addItemWithTitle:@(kProfiles[i].title) action:nil keyEquivalent:@""];
        item.tag = (NSInteger)i;
    }
    [popup.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *custom = [popup.menu addItemWithTitle:
        [NSString stringWithFormat:@"自定义…   %u × %u", self.customLogicalWidth, self.customLogicalHeight]
        action:nil keyEquivalent:@""];
    custom.tag = -100;
    [popup selectItemWithTag:(self.selectedProfile < kProfileCount ? (NSInteger)self.selectedProfile : -100)];

    NSTextField *refreshLabel = [NSTextField labelWithString:@"刷新率"];
    refreshLabel.frame = NSMakeRect(0, 8, 62, 24);
    NSPopUpButton *refreshPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(68, 4, 160, 30) pullsDown:NO];
    NSTextField *refreshHint = [NSTextField labelWithString:@"高刷新率会增加 GPU 与传输带宽占用"];
    refreshHint.textColor = NSColor.secondaryLabelColor;
    refreshHint.font = [NSFont systemFontOfSize:11];
    refreshHint.frame = NSMakeRect(238, 8, 162, 24);
    [settingsView addSubview:resolutionLabel];
    [settingsView addSubview:popup];
    [settingsView addSubview:refreshLabel];
    [settingsView addSubview:refreshPopup];
    [settingsView addSubview:refreshHint];
    alert.accessoryView = settingsView;
    self.settingsResolutionPopup = popup;
    self.settingsRefreshPopup = refreshPopup;
    self.settingsRefreshHint = refreshHint;
    popup.target = self;
    popup.action = @selector(settingsResolutionChanged:);
    [self settingsResolutionChanged:popup];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSArray *nowPhysical = [self physicalDisplayIDs];
    if (!nowPhysical || (nowPhysical.count && !self.virtualMirrorEnabled)) { [self showError:@"显示器连接已变化，请重新打开显示设置。原设置未更改。"]; return; }
    double requestedRate = [refreshPopup.selectedItem.representedObject doubleValue];
    NSInteger selection = popup.selectedItem.tag;
    if (selection == -100) {
        [self showCustomResolutionAtRate:requestedRate];
        return;
    }
    // Let preflight explain which display/mode is unavailable; never switch
    // to an arbitrary fallback when the popup has no matching rates.
    if (requestedRate <= 0) requestedRate = self.selectedRefreshRate;
    [self applyVirtualProfile:(NSUInteger)selection width:self.customLogicalWidth height:self.customLogicalHeight rate:requestedRate];
}

- (void)applyVirtualProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate {
    if (self.virtualMirrorEnabled) { [self applyVirtualMirrorProfile:profile width:width height:height rate:rate confirm:YES]; return; }
    NSArray *physical=[self physicalDisplayIDs];
    if (!physical || physical.count) { [self showError:@"显示器连接已变化，请重新打开显示设置。原设置未更改。"]; return; }
    unsigned int oldWidth=self.physicalPixelWidth,oldHeight=self.physicalPixelHeight;
    self.physicalPixelWidth=0; self.physicalPixelHeight=0;
    [self applyUnifiedSettingsProfile:profile width:width height:height rate:rate];
    if (!self.lastSettingsApplyKept) { self.physicalPixelWidth=oldWidth; self.physicalPixelHeight=oldHeight; }
}

// Native geometry and refresh rates are kept together; normal-density modes
// must not be mislabeled as HiDPI or filtered out of a physical screen picker.
- (NSArray<NSDictionary *> *)publicNativeFormatsForDisplay:(CGDirectDisplayID)display {
    NSMutableArray *formats=[NSMutableArray array];
    CFArrayRef modes=CGDisplayCopyAllDisplayModes(display,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    for (id value in (__bridge NSArray *)modes) {
        CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
        size_t w=CGDisplayModeGetWidth(mode),h=CGDisplayModeGetHeight(mode),pw=CGDisplayModeGetPixelWidth(mode),ph=CGDisplayModeGetPixelHeight(mode);
        double rate=CGDisplayModeGetRefreshRate(mode);
        if (!CGDisplayModeIsUsableForDesktopGUI(mode) || w<640 || h<480 || w>5120 || h>4320 || !isfinite(rate) || rate<=0 || rate>1000) continue;
        [formats addObject:@{@"width":@(w),@"height":@(h),@"pixelWidth":@(pw),@"pixelHeight":@(ph),@"rates":@[@(rate)]}];
    }
    if (modes) CFRelease(modes);
    return formats;
}

- (NSArray<NSDictionary *> *)hiddenNativeFormatsForDisplay:(CGDirectDisplayID)display {
    return RDNMHiddenFormatsForDisplay(display);
}

- (NSArray<NSDictionary *> *)nativeFormatsForDisplays:(NSArray<NSNumber *> *)physical {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *common = [NSMutableDictionary dictionary];
    BOOL first = YES;
    for (NSNumber *display in physical) {
        NSMutableDictionary<NSString *, NSMutableDictionary *> *formats = [NSMutableDictionary dictionary];
        NSMutableArray *candidates=[[self publicNativeFormatsForDisplay:display.unsignedIntValue] mutableCopy];
        if (!candidates) candidates=[NSMutableArray array];
        if (physical.count==1 && !self.virtualMirrorEnabled && !self.displays.count && !self.mirroredPhysicalDisplay && !self.mirrorOriginals.count && RDDesiredVirtualCount(self.selectedDisplayCount,self.preferPhysicalDisplays,physical.count)==0)
            [candidates addObjectsFromArray:[self hiddenNativeFormatsForDisplay:display.unsignedIntValue]];
        for (NSDictionary *candidate in candidates) {
            NSUInteger w=[candidate[@"width"] unsignedIntegerValue],h=[candidate[@"height"] unsignedIntegerValue],pw=[candidate[@"pixelWidth"] unsignedIntegerValue],ph=[candidate[@"pixelHeight"] unsignedIntegerValue];
            NSString *key = [NSString stringWithFormat:@"%zu/%zu/%zu/%zu",w,h,pw,ph];
            if (!formats[key]) formats[key] = [@{@"width":@(w),@"height":@(h),@"pixelWidth":@(pw),@"pixelHeight":@(ph),@"rates":[NSMutableArray array]} mutableCopy];
            NSMutableArray *rates = formats[key][@"rates"];
            for (NSNumber *rate in candidate[@"rates"]) {
                BOOL duplicate=NO;
                for (NSNumber *existing in rates) if (fabs(existing.doubleValue-rate.doubleValue)<0.01) duplicate=YES;
                if (!duplicate) [rates addObject:rate];
            }
        }
        if (first) { [common addEntriesFromDictionary:formats]; first = NO; }
        else for (NSString *key in common.allKeys) {
            NSMutableArray *rates = common[key][@"rates"];
            NSArray *other = formats[key][@"rates"] ?: @[];
            NSIndexSet *unavailable = [rates indexesOfObjectsPassingTest:^BOOL(NSNumber *rate, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                for (NSNumber *candidate in other) if (fabs(candidate.doubleValue-rate.doubleValue)<0.6) return NO;
                return YES;
            }];
            [rates removeObjectsAtIndexes:unavailable];
            if (!rates.count) [common removeObjectForKey:key];
        }
    }
    return [common.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *key in @[@"width",@"height",@"pixelWidth",@"pixelHeight"]) {
            NSComparisonResult result = [a[key] compare:b[key]];
            if (result != NSOrderedSame) return result;
        }
        return NSOrderedSame;
    }];
}

- (void)nativeFormatChanged:(id)sender {
    (void)sender;
    double previous = [self.nativeRatePopup.selectedItem.representedObject doubleValue];
    if (previous<=0) previous=self.selectedRefreshRate;
    [self.nativeRatePopup removeAllItems];
    NSArray *rates = [self.nativeFormatPopup.selectedItem.representedObject[@"rates"] sortedArrayUsingSelector:@selector(compare:)];
    self.nativeApplyButton.enabled=rates.count>0;
    for (NSNumber *rate in rates) {
        [self.nativeRatePopup addItemWithTitle:[NSString stringWithFormat:@"%g Hz",rate.doubleValue]];
        self.nativeRatePopup.lastItem.representedObject=rate;
    }
    for (NSMenuItem *item in self.nativeRatePopup.itemArray) if (fabs([item.representedObject doubleValue]-previous)<0.6) { [self.nativeRatePopup selectItem:item]; break; }
}

- (void)populateNativeFormats:(NSArray<NSDictionary *> *)formats inPopup:(NSPopUpButton *)sizes currentMode:(CGDisplayModeRef)current {
    [sizes removeAllItems];
    sizes.menu.autoenablesItems=NO;
    NSMutableArray<NSMutableArray *> *groups=[NSMutableArray arrayWithArray:@[[NSMutableArray array],[NSMutableArray array],[NSMutableArray array]]];
    for (NSDictionary *format in formats) {
        NSUInteger w=[format[@"width"] unsignedIntegerValue],h=[format[@"height"] unsignedIntegerValue],pw=[format[@"pixelWidth"] unsignedIntegerValue],ph=[format[@"pixelHeight"] unsignedIntegerValue];
        NSUInteger group=pw==w && ph==h ? 0 : (pw==w*2 && ph==h*2 ? 1 : 2);
        [groups[group] addObject:format];
    }
    NSArray *titles=@[@"普通",@"HiDPI",@"其他缩放"];
    NSMenuItem *selected=nil,*firstFormat=nil;
    for (NSUInteger group=0;group<groups.count;group++) {
        if (!groups[group].count) continue;
        if (sizes.numberOfItems) [sizes.menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *header=[sizes.menu addItemWithTitle:titles[group] action:nil keyEquivalent:@""];
        header.enabled=NO;
        NSArray *ordered=[groups[group] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            for (NSString *key in @[@"width",@"height",@"pixelWidth",@"pixelHeight"]) {
                NSComparisonResult result=[a[key] compare:b[key]];
                if (result!=NSOrderedSame) return result;
            }
            return NSOrderedSame;
        }];
        for (NSDictionary *format in ordered) {
            unsigned int w=[format[@"width"] unsignedIntValue],h=[format[@"height"] unsignedIntValue],pw=[format[@"pixelWidth"] unsignedIntValue],ph=[format[@"pixelHeight"] unsignedIntValue];
            NSString *density=group==0 ? @"普通" : (group==1 ? @"HiDPI" : [NSString stringWithFormat:@"渲染 %u × %u",pw,ph]);
            [sizes addItemWithTitle:[NSString stringWithFormat:@"%u × %u · %@",w,h,density]];
            NSMenuItem *item=sizes.lastItem;
            item.representedObject=format; item.enabled=YES; item.indentationLevel=1;
            if (!firstFormat) firstFormat=item;
            if (current && CGDisplayModeGetWidth(current)==w && CGDisplayModeGetHeight(current)==h && CGDisplayModeGetPixelWidth(current)==pw && CGDisplayModeGetPixelHeight(current)==ph) selected=item;
        }
    }
    if (selected ?: firstFormat) [sizes selectItem:selected ?: firstFormat];
}

- (void)showPhysicalResolutionPicker:(NSArray<NSNumber *> *)physical {
    NSArray *formats = [self nativeFormatsForDisplays:physical];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"统一显示设置";
    NSMutableArray *names = [NSMutableArray array];
    for (NSNumber *display in physical) [names addObject:PhysicalDisplayName(display.unsignedIntValue)];
    BOOL mainPhysical = [physical containsObject:@(CGMainDisplayID())];
    alert.informativeText = [NSString stringWithFormat:@"当前主屏：%@ · %@\n%@。切换后 15 秒内确认，否则恢复。", mainPhysical ? @"实体屏幕" : @"虚拟屏幕", PhysicalDisplayName(CGMainDisplayID()), physical.count==1 ? [NSString stringWithFormat:@"按实体屏 %@ 的可用格式列出",names.firstObject] : @"按所有实体屏共同可用格式列出"];
    [alert addButtonWithTitle:@"应用"]; [alert addButtonWithTitle:@"取消"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,420,84)];
    NSTextField *sizeLabel = [NSTextField labelWithString:@"分辨率"]; sizeLabel.frame=NSMakeRect(0,48,62,24);
    NSTextField *rateLabel = [NSTextField labelWithString:@"刷新率"]; rateLabel.frame=NSMakeRect(0,8,62,24);
    NSPopUpButton *sizes = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(68,44,352,30) pullsDown:NO];
    NSPopUpButton *rates = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(68,4,220,30) pullsDown:NO];
    CGDirectDisplayID display=physical.firstObject.unsignedIntValue;
    NSSize desktop=CGDisplayBounds(display).size;double rotation=CGDisplayRotation(display);
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
    BOOL consistent=current && RDLogicalSizeMatchesDesktop(CGDisplayModeGetWidth(current),CGDisplayModeGetHeight(current),desktop,rotation);
    [self populateNativeFormats:formats inPopup:sizes currentMode:consistent?current:NULL];
    if (!consistent && formats.count) {
        if ([self selectSavedNativeFormatInPopup:sizes desktopSize:desktop rotation:rotation])
            alert.informativeText=[alert.informativeText stringByAppendingString:@"\n已按上次保留的格式预选。"];
        else { [sizes selectItem:nil];alert.informativeText=[alert.informativeText stringByAppendingString:@"\n请选择要应用的格式。"];}
    }
    if (!formats.count) { [sizes addItemWithTitle:@"没有共同可用的固定刷新率模式"]; sizes.enabled=NO; alert.buttons.firstObject.enabled=NO; }
    self.nativeFormatPopup=sizes; self.nativeRatePopup=rates; self.nativeApplyButton=alert.buttons.firstObject;
    sizes.target=self; sizes.action=@selector(nativeFormatChanged:);
    [self nativeFormatChanged:nil];
    if (current) {
        double hz=consistent?CGDisplayModeGetRefreshRate(current):self.selectedRefreshRate;
        for (NSMenuItem *item in rates.itemArray) if (fabs([item.representedObject doubleValue]-hz)<0.6) { [rates selectItem:item]; break; }
        CFRelease(current);
    }
    for (NSView *control in @[sizeLabel,rateLabel,sizes,rates]) [view addSubview:control];
    alert.accessoryView=view;
    if ([alert runModal]!=NSAlertFirstButtonReturn || !formats.count) return;
    NSArray *connected=[self physicalDisplayIDs];
    if (!connected || ![[NSSet setWithArray:connected] isEqualToSet:[NSSet setWithArray:physical]]) {
        [self showError:@"显示器连接已变化，请重新打开显示设置。原设置未更改。"]; return;
    }
    NSDictionary *format=sizes.selectedItem.representedObject;
    [self applyPhysicalFormat:format physical:physical rate:[rates.selectedItem.representedObject doubleValue]];
}

- (BOOL)selectSavedNativeFormatInPopup:(NSPopUpButton *)popup desktopSize:(NSSize)desktop rotation:(double)rotation {
    DisplayProfile saved=[self currentProfile];
    if (!RDLogicalSizeMatchesDesktop(saved.logicalWidth,saved.logicalHeight,desktop,rotation)) return NO;
    NSUInteger pw=self.physicalPixelWidth ?: saved.width,ph=self.physicalPixelHeight ?: saved.height;
    for (NSMenuItem *item in popup.itemArray) {
        NSDictionary *format=item.representedObject;
        if ([format[@"width"] unsignedIntegerValue]==saved.logicalWidth && [format[@"height"] unsignedIntegerValue]==saved.logicalHeight && [format[@"pixelWidth"] unsignedIntegerValue]==pw && [format[@"pixelHeight"] unsignedIntegerValue]==ph) {
            [popup selectItem:item];return YES;
        }
    }
    return NO;
}

- (NSDictionary *)hiddenNativePlanForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight
    rate:(double)rate error:(NSString **)error {
    return RDHiddenNativeModePlan(ids,width,height,pixelWidth,pixelHeight,rate,error);
}

- (BOOL)applyHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error { return RDApplyHiddenNativeModePlan(plan,error); }
- (BOOL)hiddenNativePlanIsCurrent:(NSDictionary *)plan error:(NSString **)error { return RDNativePlanTargetIsCurrent(plan,error); }
- (BOOL)restoreHiddenNativePlan:(NSDictionary *)plan error:(NSString **)error { return RDRestoreNativePlanOriginal(plan,error); }

- (void)applyPhysicalFormat:(NSDictionary *)format physical:(NSArray<NSNumber *> *)physical rate:(double)rate {
    if (self.applyingDisplaySettings || self.reconcilingDisplays) return;
    self.lastSettingsApplyKept=NO;
    if (!self.displayManagementEnabled) { [self showError:@"请先启用屏幕管理，再应用显示设置。"]; return; }
    if (self.virtualMirrorEnabled || self.mirroredPhysicalDisplay || self.mirrorOriginals.count) {
        [self showError:@"显示布局已变化，请重新打开显示设置。原设置未更改。"]; return;
    }
    NSUInteger width=[format[@"width"] unsignedIntegerValue],height=[format[@"height"] unsignedIntegerValue];
    NSUInteger pixelWidth=[format[@"pixelWidth"] unsignedIntegerValue],pixelHeight=[format[@"pixelHeight"] unsignedIntegerValue];
    if (width<640 || height<480 || width>5120 || height>4320 || !pixelWidth || !pixelHeight || pixelWidth>32768 || pixelHeight>32768 || !isfinite(rate) || rate<=0 || rate>1000) {
        [self showError:@"显示格式参数无效，原设置未更改。"]; return;
    }
    if (!physical.count || ![self topologyMatchesPhysical:physical virtualIDs:[self IDsForVirtualDisplays:self.displays]]) {
        [self showError:@"显示器连接已变化，请重新打开显示设置。原设置未更改。"]; return;
    }
    unsigned int oldPixelWidth=self.physicalPixelWidth,oldPixelHeight=self.physicalPixelHeight;
    BOOL independentPhysical=physical.count==1 && !self.virtualMirrorEnabled && !self.displays.count && !self.mirroredPhysicalDisplay && !self.mirrorOriginals.count && RDDesiredVirtualCount(self.selectedDisplayCount,self.preferPhysicalDisplays,physical.count)==0;
    self.physicalPixelWidth=(unsigned int)pixelWidth; self.physicalPixelHeight=(unsigned int)pixelHeight;
    NSString *error=nil;
    NSDictionary *publicPlan=[self modePlanForDisplays:physical width:(unsigned int)width height:(unsigned int)height rate:rate error:&error];
    if (publicPlan && !independentPhysical) {
        [self applyUnifiedSettingsProfile:kProfileCount width:(unsigned int)width height:(unsigned int)height rate:rate];
        if (!self.lastSettingsApplyKept) { self.physicalPixelWidth=oldPixelWidth; self.physicalPixelHeight=oldPixelHeight; }
        return;
    }
    self.physicalPixelWidth=oldPixelWidth; self.physicalPixelHeight=oldPixelHeight;
    if (!independentPhysical || (!publicPlan && (pixelWidth!=width*2 || pixelHeight!=height*2))) {
        [self showError:error ?: @"当前显示布局无法应用所选格式，原设置未更改。"]; return;
    }
    error=nil;
    NSDictionary *plan=[self hiddenNativePlanForDisplays:physical width:(unsigned int)width height:(unsigned int)height pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight rate:rate error:&error];
    if (!plan) { [self showError:error ?: @"系统未提供所选的精确格式，原设置未更改。"]; return; }
    self.applyingDisplaySettings=YES;
    NSUInteger generation=++self.displayChangeGeneration;
    self.failedSettingsSignature=nil; self.displaySettingsIssue=nil;
    BOOL kept=NO;
    @try {
        if ([self applyHiddenNativePlan:plan error:&error]) {
            BOOL confirmed=[self confirmUnifiedDisplaySettings];
            if (generation!=self.displayChangeGeneration) {
                error=@"显示设置操作已更新，已停止旧操作。";
            } else {
                BOOL topology=[self topologyMatchesPhysical:physical virtualIDs:@[]];
                if (confirmed && topology && [self hiddenNativePlanIsCurrent:plan error:&error]) {
                    self.selectedProfile=kProfileCount; self.customLogicalWidth=(unsigned int)width; self.customLogicalHeight=(unsigned int)height;
                    self.selectedRefreshRate=rate; self.physicalPixelWidth=(unsigned int)pixelWidth; self.physicalPixelHeight=(unsigned int)pixelHeight;
                    self.unifiedSettingsEnabled=YES; self.suspendSavedSettings=NO;
                    [self persistUnifiedSettings]; kept=YES; error=nil;
                } else {
                    NSString *restoreError=nil;
                    BOOL restored=topology && [self restoreHiddenNativePlan:plan error:&restoreError];
                    error=restored ? @"未保留新设置，已核对操作前配置。" : (restoreError ?: @"显示状态或连接已变化，未覆盖当前设置。请检查系统显示器设置。");
                }
            }
        }
    } @finally {
        if (!kept && generation==self.displayChangeGeneration) self.suspendSavedSettings=YES;
        self.lastSettingsApplyKept=kept; self.displaySettingsIssue=error;
        self.applyingDisplaySettings=NO;
        [self rebuildMenu];
    }
    if (error.length) [self showError:error];
    [self scheduleDisplayReconciliation];
}

// Only expose rates matching the selected logical size AND 2x pixel size.
- (NSArray<NSNumber *> *)hiDPIRatesForDisplay:(CGDirectDisplayID)display width:(unsigned int)width height:(unsigned int)height {
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    NSMutableArray<NSNumber *> *rates = [NSMutableArray array];
    if (modes) {
        for (id value in (__bridge NSArray *)modes) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)value;
            double rate = CGDisplayModeGetRefreshRate(mode);
            if (!CGDisplayModeIsUsableForDesktopGUI(mode) || !RDMatchesHiDPI(CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode), CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode), rate, width, height, rate)) continue;
            BOOL duplicate = NO;
            for (NSNumber *existing in rates) if (fabs(existing.doubleValue-rate) < 0.01) duplicate = YES;
            if (!duplicate) [rates addObject:@(rate)];
        }
        CFRelease(modes);
    }
    return [rates sortedArrayUsingSelector:@selector(compare:)];
}

- (void)settingsResolutionChanged:(id)sender {
    (void)sender;
    NSInteger selection = self.settingsResolutionPopup.selectedItem.tag;
    unsigned int width = selection >= 0 && (NSUInteger)selection < kProfileCount ? kProfiles[selection].logicalWidth : self.customLogicalWidth;
    unsigned int height = selection >= 0 && (NSUInteger)selection < kProfileCount ? kProfiles[selection].logicalHeight : self.customLogicalHeight;
    if (self.settingsCustomWidth) {
        width = (unsigned int)MAX(0, self.settingsCustomWidth.integerValue);
        height = (unsigned int)MAX(0, self.settingsCustomHeight.integerValue);
    }
    NSArray *physical = [self physicalDisplayIDs];
    NSMutableArray<NSNumber *> *rates = [NSMutableArray arrayWithArray:@[@30,@60,@75,@90,@120,@144,@165]];
    if (self.virtualMirrorEnabled && physical.count) {
        NSIndexSet *unsupported=[rates indexesOfObjectsPassingTest:^BOOL(NSNumber *rate, NSUInteger idx, BOOL *stop) {
            (void)idx; (void)stop;
            return [self physicalMirrorModePlan:physical rate:rate.doubleValue error:NULL]==nil;
        }];
        [rates removeObjectsAtIndexes:unsupported];
    } else if (physical.count) {
        [rates setArray:[self hiDPIRatesForDisplay:[physical.firstObject unsignedIntValue] width:width height:height]];
        for (NSNumber *display in physical) {
            NSArray *available = [self hiDPIRatesForDisplay:display.unsignedIntValue width:width height:height];
            NSIndexSet *unavailable = [rates indexesOfObjectsPassingTest:^BOOL(NSNumber *rate, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                for (NSNumber *candidate in available) if (fabs(candidate.doubleValue-rate.doubleValue)<0.6) return NO;
                return YES;
            }];
            [rates removeObjectsAtIndexes:unavailable];
        }
    }
    NSPopUpButton *popup = self.settingsRefreshPopup;
    double preferred = popup.selectedItem ? [popup.selectedItem.representedObject doubleValue] : self.selectedRefreshRate;
    [popup removeAllItems];
    for (NSNumber *rate in rates) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%g Hz", rate.doubleValue]];
        popup.lastItem.representedObject = rate;
    }
    if (!rates.count) [popup addItemWithTitle:self.virtualMirrorEnabled ? @"无共同可用刷新率" : @"无匹配的 HiDPI 模式"];
    popup.enabled = rates.count > 0;
    for (NSMenuItem *item in popup.itemArray) if (fabs([item.representedObject doubleValue]-preferred)<0.6) { [popup selectItem:item]; break; }
    self.settingsRefreshHint.stringValue = physical.count ? @"按实体屏共同可用刷新率列出" : @"无实体屏，使用虚拟屏刷新率";
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.settingsCustomWidth || notification.object == self.settingsCustomHeight) [self settingsResolutionChanged:nil];
}

- (void)showCustomResolutionAtRate:(double)rate {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"自定义 HiDPI 分辨率";
    alert.informativeText = @"输入逻辑桌面的宽度和高度。实际渲染分辨率为输入值的 2 倍。";
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"取消"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 114)];
    NSTextField *widthLabel = [NSTextField labelWithString:@"宽度"];
    widthLabel.frame = NSMakeRect(0, 42, 54, 24);
    NSTextField *widthField = [[NSTextField alloc] initWithFrame:NSMakeRect(58, 40, 100, 26)];
    widthField.stringValue = [NSString stringWithFormat:@"%u", self.customLogicalWidth];
    NSTextField *heightLabel = [NSTextField labelWithString:@"高度"];
    heightLabel.frame = NSMakeRect(0, 6, 54, 24);
    NSTextField *heightField = [[NSTextField alloc] initWithFrame:NSMakeRect(58, 4, 100, 26)];
    heightField.stringValue = [NSString stringWithFormat:@"%u", self.customLogicalHeight];
    NSTextField *preview = [NSTextField labelWithString:@"2× HiDPI 渲染"];
    preview.textColor = NSColor.secondaryLabelColor;
    preview.frame = NSMakeRect(174, 23, 126, 24);
    for (NSView *view in @[widthLabel,widthField,heightLabel,heightField,preview]) {
        NSRect frame = view.frame; frame.origin.y += 42; view.frame = frame;
    }
    NSPopUpButton *customRate = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(58, 4, 230, 30) pullsDown:NO];
    [customRate addItemWithTitle:[NSString stringWithFormat:@"%g Hz", rate]];
    customRate.lastItem.representedObject = @(rate);
    self.settingsResolutionPopup = nil;
    self.settingsRefreshPopup = customRate;
    self.settingsCustomWidth = widthField;
    self.settingsCustomHeight = heightField;
    widthField.delegate = self; heightField.delegate = self;
    [self settingsResolutionChanged:nil];
    [accessory addSubview:customRate];
    [accessory addSubview:widthLabel];
    [accessory addSubview:widthField];
    [accessory addSubview:heightLabel];
    [accessory addSubview:heightField];
    [accessory addSubview:preview];
    alert.accessoryView = accessory;
    [alert.window setInitialFirstResponder:widthField];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSInteger width = widthField.integerValue;
    NSInteger height = heightField.integerValue;
    if (width < 640 || width > 5120 || height < 480 || height > 4320) {
        NSAlert *error = [[NSAlert alloc] init];
        error.alertStyle = NSAlertStyleWarning;
        error.messageText = @"分辨率超出支持范围";
        error.informativeText = @"宽度需为 640–5120，高度需为 480–4320。";
        [error runModal];
        return;
    }

    double selectedRate = [customRate.selectedItem.representedObject doubleValue];
    if (selectedRate <= 0) {
        NSString *reason = nil;
        [self modePlanForDisplays:[self physicalDisplayIDs] width:(unsigned int)width height:(unsigned int)height rate:rate error:&reason];
        NSAlert *error = [NSAlert new];
        error.messageText = @"无法应用显示设置";
        error.informativeText = reason ?: @"当前连接没有此尺寸的共同 2× HiDPI 模式。原设置未更改。";
        [error runModal];
        return;
    }
    [self applyVirtualProfile:kProfileCount width:(unsigned int)width height:(unsigned int)height rate:selectedRate];
}

// The plan is built completely before a transaction is committed. Never choose
// a nearby resolution/refresh rate and present it as the requested setting.
- (NSDictionary<NSNumber *, id> *)modePlanForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height rate:(double)rate error:(NSString **)error {
    NSMutableDictionary *plan = [NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        CGDirectDisplayID display = key.unsignedIntValue;
        if (!CGDisplayIsOnline(display) || CGDisplayIsInMirrorSet(display)) {
            if (error) *error = @"显示器已断开或处于镜像模式；请恢复扩展显示后重试。";
            return nil;
        }
        CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
        BOOL nativePhysical = self.physicalPixelWidth && self.physicalPixelHeight && RDIsPhysicalDisplay(CGDisplayVendorNumber(display),CGDisplayModelNumber(display));
        if (modes) {
            for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
                CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                BOOL match = nativePhysical ?
                    CGDisplayModeGetWidth(mode)==width && CGDisplayModeGetHeight(mode)==height &&
                    CGDisplayModeGetPixelWidth(mode)==self.physicalPixelWidth && CGDisplayModeGetPixelHeight(mode)==self.physicalPixelHeight &&
                    RDNativeRateMatches(CGDisplayModeGetRefreshRate(mode),rate) : RDMatchesHiDPI(
                    CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode),
                    CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode),
                    CGDisplayModeGetRefreshRate(mode), width, height, rate);
                if (CGDisplayModeIsUsableForDesktopGUI(mode) && match) {
                    plan[key] = (__bridge id)mode;
                    break;
                }
            }
            CFRelease(modes);
        }
        if (!plan[key]) {
            if (nativePhysical) {
                if (error) *error=[NSString stringWithFormat:@"%@：当前连接没有桌面 %u × %u、渲染 %u × %u、%g Hz 的对应模式。可能屏幕连接或模式列表已变化，请重新打开显示设置。原设置未更改。",PhysicalDisplayName(display),width,height,self.physicalPixelWidth,self.physicalPixelHeight,rate];
                return nil;
            }
            NSArray *available = [self hiDPIRatesForDisplay:display width:width height:height];
            if (error) {
                if (available.count) {
                    NSMutableArray *labels = [NSMutableArray array];
                    for (NSNumber *hz in available) [labels addObject:[NSString stringWithFormat:@"%g Hz", hz.doubleValue]];
                    *error = [NSString stringWithFormat:@"%@：刷新率 %g Hz 无匹配模式。%u × %u 的 2× HiDPI 当前可用刷新率：%@。原设置未更改。", PhysicalDisplayName(display), rate, width, height, [labels componentsJoinedByString:@"、"]];
                } else {
                    BOOL logicalSizeAvailable = NO;
                    CFArrayRef native = CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
                    if (native) {
                        for (id value in (__bridge NSArray *)native) {
                            CGDisplayModeRef candidate = (__bridge CGDisplayModeRef)value;
                            if (CGDisplayModeIsUsableForDesktopGUI(candidate) && CGDisplayModeGetWidth(candidate)==width && CGDisplayModeGetHeight(candidate)==height) logicalSizeAvailable = YES;
                        }
                        CFRelease(native);
                    }
                    *error = [NSString stringWithFormat:@"%@：%@。原设置未更改。", PhysicalDisplayName(display), logicalSizeAvailable ? [NSString stringWithFormat:@"%u × %u 尺寸有可用模式，但 macOS 当前未提供其 2× HiDPI 模式（渲染 %u × %u）", width, height, width*2, height*2] : [NSString stringWithFormat:@"macOS 当前未提供桌面尺寸 %u × %u 的模式", width, height]];
                }
            }
            return nil;
        }
    }
    return plan;
}

- (NSDictionary<NSNumber *, id> *)currentModesForDisplays:(NSArray<NSNumber *> *)ids {
    NSMutableDictionary *modes = [NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(key.unsignedIntValue);
        if (!mode) return nil;
        modes[key] = CFBridgingRelease(mode);
    }
    return modes;
}

- (BOOL)configureModes:(NSDictionary<NSNumber *, id> *)modes {
    if (!modes.count) return YES;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) return NO;
    for (NSNumber *key in modes) {
        if (!CGDisplayIsOnline(key.unsignedIntValue)) { CGCancelDisplayConfiguration(config); return NO; }
        if (CGConfigureDisplayWithDisplayMode(config, key.unsignedIntValue, (__bridge CGDisplayModeRef)modes[key], NULL) != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(config); return NO;
        }
    }
    return CGCompleteDisplayConfiguration(config, kCGConfigureForSession) == kCGErrorSuccess;
}

- (BOOL)modesAreCurrent:(NSDictionary<NSNumber *, id> *)plan {
    for (NSNumber *key in plan) {
        if (!CGDisplayIsOnline(key.unsignedIntValue) || CGDisplayIsInMirrorSet(key.unsignedIntValue)) return NO;
        CGDisplayModeRef wanted = (__bridge CGDisplayModeRef)plan[key];
        CGDisplayModeRef actual = CGDisplayCopyDisplayMode(key.unsignedIntValue);
        if (!actual) return NO;
        BOOL equal = CGDisplayModeGetWidth(actual)==CGDisplayModeGetWidth(wanted) && CGDisplayModeGetHeight(actual)==CGDisplayModeGetHeight(wanted) &&
            CGDisplayModeGetPixelWidth(actual)==CGDisplayModeGetPixelWidth(wanted) && CGDisplayModeGetPixelHeight(actual)==CGDisplayModeGetPixelHeight(wanted) &&
            fabs(CGDisplayModeGetRefreshRate(actual)-CGDisplayModeGetRefreshRate(wanted))<0.6;
        CFRelease(actual);
        if (!equal) return NO;
    }
    return YES;
}

- (NSArray<NSNumber *> *)IDsForVirtualDisplays:(NSArray<CGVirtualDisplay *> *)displays {
    NSMutableArray *ids = [NSMutableArray array];
    for (CGVirtualDisplay *display in displays) [ids addObject:@(display.displayID)];
    return ids;
}

- (NSArray *)virtualModesForProfile:(DisplayProfile)p rate:(double)rate {
    NSMutableArray *rates=[NSMutableArray arrayWithObject:@(rate)];
    NSArray *physical=[self physicalDisplayIDs];
    for (NSNumber *candidate in @[@30,@60,@75,@90,@120,@144,@165]) {
        if (fabs(candidate.doubleValue-rate)<0.6) continue;
        if (physical.count && ![self physicalMirrorModePlan:physical rate:candidate.doubleValue error:NULL]) continue;
        [rates addObject:candidate];
    }
    NSMutableArray *modes=[NSMutableArray array];
    for (NSNumber *value in rates) {
        id mode=[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:p.logicalWidth height:p.logicalHeight refreshRate:value.doubleValue];
        if (!mode) return nil;
        [modes addObject:mode];
    }
    return modes;
}

- (BOOL)advertiseVirtualDisplays:(NSArray<CGVirtualDisplay *> *)displays profile:(DisplayProfile)p rate:(double)rate {
    if (!displays.count) return YES;
    // With hiDPI enabled this API accepts logical dimensions, not the
    // doubled backing dimensions. Passing p.width doubles the desktop twice.
    NSArray *modes=[self virtualModesForProfile:p rate:rate];
    if (!modes.count) return NO;
    CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 1; settings.modes = modes;
    BOOL accepted = YES;
    for (CGVirtualDisplay *display in displays) if (![display applySettings:settings]) accepted = NO;
    return accepted;
}

- (BOOL)topologyMatchesPhysical:(NSArray *)physical virtualIDs:(NSArray *)virtualIDs {
    NSArray *current = [self physicalDisplayIDs];
    return current && [[NSSet setWithArray:current] isEqualToSet:[NSSet setWithArray:physical]] &&
        [[self IDsForVirtualDisplays:self.displays] isEqual:virtualIDs];
}

- (BOOL)restoreModes:(NSDictionary<NSNumber *, id> *)previous {
    NSMutableDictionary *online = [NSMutableDictionary dictionary];
    for (NSNumber *key in previous) if (CGDisplayIsOnline(key.unsignedIntValue)) online[key] = previous[key];
    return [self configureModes:online];
}

- (BOOL)confirmUnifiedDisplaySettings {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"保留这些显示设置？";
    alert.informativeText = @"已应用所选桌面尺寸和刷新率。请在 15 秒内确认，超时自动恢复。";
    if (self.virtualMirrorEnabled) {
        alert.messageText=@"保留虚拟高清画面？";
        alert.informativeText=@"实体屏正在显示虚拟屏提供的 HiDPI 画面。请在 15 秒内确认，超时自动恢复原画面。";
    }
    [alert addButtonWithTitle:@"保留设置"];
    [alert addButtonWithTitle:@"恢复原设置"];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 15;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *unused) {
        (void)unused;
        if (NSProcessInfo.processInfo.systemUptime >= deadline && NSApp.modalWindow == alert.window) [NSApp abortModal];
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSModalPanelRunLoopMode];
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    [timer invalidate];
    [alert.window orderOut:nil];
    return response == NSAlertFirstButtonReturn;
}

- (void)persistUnifiedSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:(self.selectedProfile < kProfileCount ? @(kProfiles[self.selectedProfile].key) : @"custom-hidpi") forKey:@"profile"];
    [defaults setInteger:self.customLogicalWidth forKey:@"customLogicalWidth"];
    [defaults setInteger:self.customLogicalHeight forKey:@"customLogicalHeight"];
    [defaults setDouble:self.selectedRefreshRate forKey:@"refreshRate"];
    [defaults setInteger:self.physicalPixelWidth forKey:@"physicalPixelWidth"];
    [defaults setInteger:self.physicalPixelHeight forKey:@"physicalPixelHeight"];
    [defaults setBool:YES forKey:@"unifiedDisplaySettingsEnabled"];
    [defaults setBool:self.virtualMirrorEnabled forKey:@"virtualMirrorEnabled"];
    [defaults setBool:self.mirrorConfigurationConfirmed forKey:@"mirrorConfigurationConfirmed"];
}

- (NSDictionary *)mirrorSnapshotForDisplays:(NSArray<NSNumber *> *)ids {
    NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        CGDirectDisplayID display=key.unsignedIntValue;
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(display);
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
        if (!mode || !uuid) { if (mode) CFRelease(mode); if (uuid) CFRelease(uuid); return nil; }
        NSString *identity=CFBridgingRelease(CFUUIDCreateString(NULL,uuid)); CFRelease(uuid);
        CGRect bounds=CGDisplayBounds(display);
        snapshot[key]=@{@"mode":CFBridgingRelease(mode),@"mirror":@(CGDisplayMirrorsDisplay(display)),@"x":@(bounds.origin.x),@"y":@(bounds.origin.y),@"uuid":identity};
    }
    return snapshot;
}

- (NSDictionary *)mirrorRoutesForPhysical:(NSArray<NSNumber *> *)physical sources:(NSArray<NSNumber *> *)sources {
    if (!sources.count) return nil;
    NSMutableDictionary *routes=[NSMutableDictionary dictionary];
    for (NSUInteger i=0;i<physical.count;i++) routes[physical[i]]=sources[i%sources.count];
    return routes;
}

- (BOOL)mirrorRoutesAreCurrent:(NSDictionary<NSNumber *,NSNumber *> *)routes {
    for (NSNumber *key in routes) if (!CGDisplayIsOnline(key.unsignedIntValue) || !CGDisplayIsOnline([routes[key] unsignedIntValue]) || CGDisplayMirrorsDisplay(key.unsignedIntValue)!=[routes[key] unsignedIntValue]) return NO;
    return YES;
}

// The virtual source controls desktop geometry; a mirrored physical output
// still has its own hardware timing. Prefer native, unscaled scan-out modes.
- (NSDictionary *)physicalMirrorModePlan:(NSArray<NSNumber *> *)ids rate:(double)rate error:(NSString **)error {
    NSMutableDictionary *plan=[NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        CFArrayRef modes=CGDisplayCopyAllDisplayModes(key.unsignedIntValue,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
        id best=nil; BOOL bestNative=NO; size_t bestArea=0;
        if (modes) {
            for (id value in (__bridge NSArray *)modes) {
                CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
                size_t w=CGDisplayModeGetWidth(mode),h=CGDisplayModeGetHeight(mode);
                if (!CGDisplayModeIsUsableForDesktopGUI(mode) || !w || !h ||
                    w!=CGDisplayModeGetPixelWidth(mode) || h!=CGDisplayModeGetPixelHeight(mode) ||
                    fabs(CGDisplayModeGetRefreshRate(mode)-rate)>=0.6) continue;
                BOOL native=(CGDisplayModeGetIOFlags(mode)&kDisplayModeNativeFlag)!=0;
                if (!best || (native && !bestNative) || (native==bestNative && w*h>bestArea)) {
                    best=value; bestNative=native; bestArea=w*h;
                }
            }
            if (best) plan[key]=best;
            CFRelease(modes);
        }
        if (!plan[key]) {
            if (error) *error=[NSString stringWithFormat:@"%@：未提供 %g Hz 的实体输出模式。原设置未更改。",PhysicalDisplayName(key.unsignedIntValue),rate];
            return nil;
        }
    }
    return plan;
}

- (BOOL)physicalMirrorDisplays:(NSArray<NSNumber *> *)ids matchRate:(double)rate {
    for (NSNumber *key in ids) {
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(key.unsignedIntValue);
        BOOL match=mode && fabs(CGDisplayModeGetRefreshRate(mode)-rate)<0.6;
        if (mode) CFRelease(mode);
        if (!match) return NO;
    }
    return YES;
}

// A physical mode from before mirroring is not valid in every mirror set.
// Establish the route, then enumerate its derived modes instead of reusing a
// native, unscaled mode with a different desktop geometry.
- (BOOL)configureMirrorPlan:(NSDictionary *)virtualPlan physicalPlan:(NSDictionary *)physicalPlan routes:(NSDictionary *)routes sources:(NSArray *)sources {
    if (![self modesAreCurrent:virtualPlan] && ![self configureModes:virtualPlan]) { self.displaySettingsIssue=@"虚拟源模式提交失败。"; return NO; }
    if (![self mirrorRoutesAreCurrent:routes]) {
        CGDisplayConfigRef routeConfig=NULL;
        CGError status=CGBeginDisplayConfiguration(&routeConfig);
        if (status!=kCGErrorSuccess) return NO;
        for (NSNumber *key in routes) {
            status=CGConfigureDisplayMirrorOfDisplay(routeConfig,key.unsignedIntValue,[routes[key] unsignedIntValue]);
            if (status!=kCGErrorSuccess) { CGCancelDisplayConfiguration(routeConfig); self.displaySettingsIssue=[NSString stringWithFormat:@"建立镜像失败（%d）。",status]; return NO; }
        }
        int x=0;
        for (NSNumber *key in sources) {
            status=CGConfigureDisplayOrigin(routeConfig,key.unsignedIntValue,x,0);
            if (status!=kCGErrorSuccess) { CGCancelDisplayConfiguration(routeConfig); return NO; }
            x+=(int)CGDisplayModeGetWidth((__bridge CGDisplayModeRef)virtualPlan[key]);
        }
        status=CGCompleteDisplayConfiguration(routeConfig,kCGConfigureForSession);
        if (status!=kCGErrorSuccess) { self.displaySettingsIssue=[NSString stringWithFormat:@"镜像提交失败（%d）。",status]; return NO; }
    }
    NSMutableDictionary *outputPlan=[NSMutableDictionary dictionary];
    for (NSNumber *key in physicalPlan) {
        CGDisplayModeRef actual=CGDisplayCopyDisplayMode(key.unsignedIntValue);
        if (!actual) return NO;
        double rate=CGDisplayModeGetRefreshRate((__bridge CGDisplayModeRef)physicalPlan[key]);
        if (fabs(CGDisplayModeGetRefreshRate(actual)-rate)<0.6) { CFRelease(actual); continue; }
        CFArrayRef modes=CGDisplayCopyAllDisplayModes(key.unsignedIntValue,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
        if (modes) {
            for (id value in (__bridge NSArray *)modes) {
                CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
                if (CGDisplayModeIsUsableForDesktopGUI(mode) &&
                    CGDisplayModeGetWidth(mode)==CGDisplayModeGetWidth(actual) && CGDisplayModeGetHeight(mode)==CGDisplayModeGetHeight(actual) &&
                    CGDisplayModeGetPixelWidth(mode)==CGDisplayModeGetPixelWidth(actual) && CGDisplayModeGetPixelHeight(mode)==CGDisplayModeGetPixelHeight(actual) &&
                    fabs(CGDisplayModeGetRefreshRate(mode)-rate)<0.6) { outputPlan[key]=value; break; }
            }
            CFRelease(modes);
        }
        CFRelease(actual);
        if (!outputPlan[key]) { self.displaySettingsIssue=[NSString stringWithFormat:@"%@：镜像后未提供 %g Hz 的匹配输出模式。",PhysicalDisplayName(key.unsignedIntValue),rate]; return NO; }
    }
    if (!outputPlan.count) return YES;
    CGDisplayConfigRef config=NULL;
    if (CGBeginDisplayConfiguration(&config)!=kCGErrorSuccess) return NO;
    NSMutableDictionary *modes=[outputPlan mutableCopy]; [modes addEntriesFromDictionary:virtualPlan];
    for (NSNumber *key in modes) {
        CGError status=CGConfigureDisplayWithDisplayMode(config,key.unsignedIntValue,(__bridge CGDisplayModeRef)modes[key],NULL);
        if (status!=kCGErrorSuccess) { CGCancelDisplayConfiguration(config); self.displaySettingsIssue=[NSString stringWithFormat:@"%@：刷新率配置失败（%d）。",PhysicalDisplayName(key.unsignedIntValue),status]; return NO; }
    }
    CGError status=CGCompleteDisplayConfiguration(config,kCGConfigureForSession);
    if (status!=kCGErrorSuccess) self.displaySettingsIssue=[NSString stringWithFormat:@"刷新率同步提交失败（%d）。",status];
    return status==kCGErrorSuccess;
}

- (BOOL)restoreMirrorSnapshot:(NSDictionary<NSNumber *,NSDictionary *> *)snapshot {
    CGDisplayConfigRef config=NULL;
    if (CGBeginDisplayConfiguration(&config)!=kCGErrorSuccess) return NO;
    for (NSNumber *key in snapshot) {
        CGDirectDisplayID display=key.unsignedIntValue;
        if (!CGDisplayIsOnline(display)) continue;
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
        NSString *identity=uuid ? CFBridgingRelease(CFUUIDCreateString(NULL,uuid)) : nil;
        if (uuid) CFRelease(uuid);
        NSDictionary *previous=snapshot[key];
        if (![identity isEqual:previous[@"uuid"]]) continue; // Do not touch a replacement display reusing an ID.
        CGDirectDisplayID original=[previous[@"mirror"] unsignedIntValue];
        if (!CGDisplayIsOnline(original)) original=kCGNullDirectDisplay;
        if (CGConfigureDisplayWithDisplayMode(config,display,(__bridge CGDisplayModeRef)previous[@"mode"],NULL)!=kCGErrorSuccess ||
            CGConfigureDisplayMirrorOfDisplay(config,display,original)!=kCGErrorSuccess ||
            (!original && CGConfigureDisplayOrigin(config,display,[previous[@"x"] intValue],[previous[@"y"] intValue])!=kCGErrorSuccess)) {
            CGCancelDisplayConfiguration(config); return NO;
        }
    }
    if (CGCompleteDisplayConfiguration(config,kCGConfigureForSession)!=kCGErrorSuccess) return NO;
    for (NSNumber *key in snapshot) {
        CGDirectDisplayID display=key.unsignedIntValue;
        if (!CGDisplayIsOnline(display)) continue;
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
        NSString *identity=uuid ? CFBridgingRelease(CFUUIDCreateString(NULL,uuid)) : nil;
        if (uuid) CFRelease(uuid);
        NSDictionary *previous=snapshot[key];
        if (![identity isEqual:previous[@"uuid"]]) continue;
        CGDirectDisplayID original=[previous[@"mirror"] unsignedIntValue];
        if (!CGDisplayIsOnline(original)) original=kCGNullDirectDisplay;
        if (CGDisplayMirrorsDisplay(display)!=original) return NO;
        if (original) {
            CGDisplayModeRef actual=CGDisplayCopyDisplayMode(display);
            BOOL same=actual && fabs(CGDisplayModeGetRefreshRate(actual)-CGDisplayModeGetRefreshRate((__bridge CGDisplayModeRef)previous[@"mode"]))<0.6;
            if (actual) CFRelease(actual);
            if (!same) return NO;
        }
        if (!original) {
            CGDisplayModeRef wanted=(__bridge CGDisplayModeRef)previous[@"mode"],actual=CGDisplayCopyDisplayMode(display);
            BOOL same=actual && CGDisplayModeGetWidth(actual)==CGDisplayModeGetWidth(wanted) && CGDisplayModeGetHeight(actual)==CGDisplayModeGetHeight(wanted) && CGDisplayModeGetPixelWidth(actual)==CGDisplayModeGetPixelWidth(wanted) && CGDisplayModeGetPixelHeight(actual)==CGDisplayModeGetPixelHeight(wanted) && fabs(CGDisplayModeGetRefreshRate(actual)-CGDisplayModeGetRefreshRate(wanted))<0.6;
            if (actual) CFRelease(actual);
            if (!same) return NO;
        }
    }
    return YES;
}

- (BOOL)restoreVirtualMirrorTargets {
    if (!self.mirrorOriginals.count) return YES;
    if (![self restoreMirrorSnapshot:self.mirrorOriginals]) return NO;
    [self.mirrorOriginals removeAllObjects];
    return YES;
}

- (NSDictionary *)virtualModePlan:(NSArray<NSNumber *> *)ids profile:(DisplayProfile)p rate:(double)rate {
    NSMutableDictionary *plan=[NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        CFArrayRef modes=CGDisplayCopyAllDisplayModes(key.unsignedIntValue,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
        if (modes) {
            for (id value in (__bridge NSArray *)modes) {
                CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
                if (CGDisplayModeIsUsableForDesktopGUI(mode) && RDMatchesHiDPI(CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetPixelWidth(mode),CGDisplayModeGetPixelHeight(mode),CGDisplayModeGetRefreshRate(mode),p.logicalWidth,p.logicalHeight,rate)) { plan[key]=value; break; }
            }
            CFRelease(modes);
        }
        if (!plan[key]) return nil;
    }
    return plan;
}

- (BOOL)virtualSources:(NSArray<NSNumber *> *)ids matchProfile:(DisplayProfile)p rate:(double)rate {
    if (!ids.count) return NO;
    for (NSNumber *key in ids) {
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(key.unsignedIntValue);
        BOOL match=mode && !CGDisplayMirrorsDisplay(key.unsignedIntValue) && RDMatchesHiDPI(CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetPixelWidth(mode),CGDisplayModeGetPixelHeight(mode),CGDisplayModeGetRefreshRate(mode),p.logicalWidth,p.logicalHeight,rate);
        if (mode) CFRelease(mode);
        if (!match) return NO;
    }
    return YES;
}

- (void)applyVirtualMirrorProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate confirm:(BOOL)confirm {
    self.lastSettingsApplyKept=NO;
    if (self.applyingDisplaySettings || !self.displayManagementEnabled) return;
    if (profile>kProfileCount || (profile==kProfileCount && (width<640 || height<480 || width>5120 || height>4320)) || !isfinite(rate) || rate<=0 || rate>240) { [self showError:@"虚拟屏设置超出支持范围。"]; return; }
    NSArray *physical=[self physicalDisplayIDs];
    if (!physical) { [self showError:@"无法读取当前显示器；未更改设置。"]; return; }
    NSString *preflightError=nil;
    NSDictionary *physicalPlan=[self physicalMirrorModePlan:physical rate:rate error:&preflightError];
    if (!physicalPlan) { self.suspendSavedSettings=YES; [self showError:preflightError]; return; }
    if (self.displays.count && self.displays.count!=self.selectedDisplayCount) { [self showError:@"虚拟屏数量正在变化，请暂停后重新启用。"]; return; }
    NSDictionary *beforeTargets=[self mirrorSnapshotForDisplays:physical];
    NSArray *oldSources=[self IDsForVirtualDisplays:self.displays];
    NSDictionary *beforeSources=[self currentModesForDisplays:oldSources];
    if (!beforeTargets || !beforeSources) { [self showError:@"无法保存当前显示状态；未更改设置。"]; return; }
    NSArray *previousVirtuals=self.displays ?: @[];
    NSDictionary *previousOriginals=[self.mirrorOriginals copy] ?: @{};
    DisplayProfile previousProfile=[self currentProfile];
    NSUInteger previousSelection=self.selectedProfile;
    unsigned int previousWidth=self.customLogicalWidth,previousHeight=self.customLogicalHeight;
    double previousRate=self.selectedRefreshRate;
    DisplayProfile requested=profile<kProfileCount ? kProfiles[profile] : (DisplayProfile){"custom-hidpi","Custom HiDPI",width*2,height*2,width,height,YES};
    self.applyingDisplaySettings=YES; ++self.displayChangeGeneration;
    self.displaySettingsIssue=nil;
    self.selectedProfile=profile; self.customLogicalWidth=width; self.customLogicalHeight=height; self.selectedRefreshRate=rate;
    BOOL kept=NO,restored=YES;
    NSString *error=nil;
    @try {
        self.mirrorOriginals=[previousOriginals mutableCopy];
        for (NSNumber *key in beforeTargets) if (![self.mirrorOriginals[key][@"uuid"] isEqual:beforeTargets[key][@"uuid"]]) self.mirrorOriginals[key]=beforeTargets[key];
        BOOL advertised;
        if (!previousVirtuals.count) { self.displays=[self createVirtualDisplays:self.selectedDisplayCount]; advertised=self.displays.count==self.selectedDisplayCount; }
        else advertised=[self virtualModePlan:oldSources profile:requested rate:rate]!=nil || [self advertiseVirtualDisplays:self.displays profile:requested rate:rate];
        NSArray *sources=[self IDsForVirtualDisplays:self.displays];
        NSDictionary *plan=nil;
        for (NSUInteger attempt=0;advertised && attempt<10 && !plan;attempt++) {
            plan=[self virtualModePlan:sources profile:requested rate:rate];
            if (!plan) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NSDictionary *routes=[self mirrorRoutesForPhysical:physical sources:sources];
        if (!advertised) error=self.displaySettingsIssue ?: @"虚拟屏未接受模式定义，正在恢复原画面。";
        else if (!plan || !routes) {
            NSMutableArray *available=[NSMutableArray array];
            for (NSNumber *source in sources) {
                CFArrayRef modes=CGDisplayCopyAllDisplayModes(source.unsignedIntValue,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
                if (modes) {
                    for (id value in (__bridge NSArray *)modes) {
                        CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
                        if (CGDisplayModeIsUsableForDesktopGUI(mode)) [available addObject:[NSString stringWithFormat:@"%zu×%zu（渲染 %zu×%zu），%g Hz",CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetPixelWidth(mode),CGDisplayModeGetPixelHeight(mode),CGDisplayModeGetRefreshRate(mode)]];
                    }
                    CFRelease(modes);
                }
            }
            error=[NSString stringWithFormat:@"虚拟屏未提供请求的 %u×%u HiDPI、%g Hz。系统当前返回：%@。已恢复原画面。",requested.logicalWidth,requested.logicalHeight,rate,available.count ? [available componentsJoinedByString:@"；"] : @"尚无可用模式"];
        }
        else if (!([self virtualSources:sources matchProfile:requested rate:rate] && [self mirrorRoutesAreCurrent:routes] && [self physicalMirrorDisplays:physical matchRate:rate]) &&
                 ![self configureMirrorPlan:plan physicalPlan:physicalPlan routes:routes sources:sources]) error=self.displaySettingsIssue ?: @"macOS 拒绝实体刷新率或虚拟镜像设置，正在恢复原画面。";
        else if (![self virtualSources:sources matchProfile:requested rate:rate] || ![self mirrorRoutesAreCurrent:routes] || ![self physicalMirrorDisplays:physical matchRate:rate]) error=@"实体屏与虚拟屏的实际刷新率或镜像方向不匹配，正在恢复原画面。";
        else if ((!confirm || [self confirmUnifiedDisplaySettings]) && [self topologyMatchesPhysical:physical virtualIDs:sources] && [self virtualSources:sources matchProfile:requested rate:rate] && [self mirrorRoutesAreCurrent:routes] && [self physicalMirrorDisplays:physical matchRate:rate]) {
            self.unifiedSettingsEnabled=YES; self.suspendSavedSettings=NO; self.mirrorConfigurationConfirmed=YES;
            [self persistUnifiedSettings]; kept=YES;
        } else error=@"未确认或屏幕连接发生变化，已恢复原画面。";
        if (!kept) {
            BOOL advertRestored=!previousVirtuals.count || [self virtualModePlan:oldSources profile:previousProfile rate:previousRate]!=nil || [self advertiseVirtualDisplays:previousVirtuals profile:previousProfile rate:previousRate];
            BOOL sourcesRestored=[self restoreModes:beforeSources];
            BOOL targetsRestored=[self restoreMirrorSnapshot:beforeTargets];
            restored=advertRestored && sourcesRestored && targetsRestored;
            if (!restored) error=@"恢复原画面未全部成功，已保留虚拟屏避免丢失画面；请勿退出软件。";
        }
    } @finally {
        if (!kept) {
            self.selectedProfile=previousSelection; self.customLogicalWidth=previousWidth; self.customLogicalHeight=previousHeight; self.selectedRefreshRate=previousRate;
            if (restored) { self.displays=[previousVirtuals mutableCopy]; self.mirrorOriginals=[previousOriginals mutableCopy]; }
            self.suspendSavedSettings=YES;
        }
        self.applyingDisplaySettings=NO; self.lastSettingsApplyKept=kept; self.displaySettingsIssue=error;
        [self rebuildMenu];
    }
    if (error) [self showError:error];
    if (kept) [self scheduleDisplayReconciliation];
}

- (void)applyUnifiedSettingsProfile:(NSUInteger)profile width:(unsigned int)width height:(unsigned int)height rate:(double)rate {
    if (self.virtualMirrorEnabled) { [self applyVirtualMirrorProfile:profile width:width height:height rate:rate confirm:YES]; return; }
    self.lastSettingsApplyKept = NO;
    if (self.applyingDisplaySettings) return;
    if (!self.displayManagementEnabled) { [self showError:@"请先启用屏幕管理，再应用统一设置。"]; return; }
    if (profile > kProfileCount || (profile == kProfileCount && (width < 640 || width > 5120 || height < 480 || height > 4320)) || !isfinite(rate) || rate <= 0 || rate > 1000) {
        [self showError:@"显示设置超出支持范围。"]; return;
    }
    NSArray *physical = [self physicalDisplayIDs];
    if (!physical || self.mirroredPhysicalDisplay) { [self showError:@"无法读取显示器，或旧镜像尚未恢复。请先恢复原镜像后重试。"]; return; }
    NSUInteger desired = self.preferPhysicalDisplays ? (physical.count >= self.selectedDisplayCount ? 0 : self.selectedDisplayCount - physical.count) : self.selectedDisplayCount;
    if (self.displays.count != desired && self.displays.count != 0) { [self showError:@"屏幕连接正在变化，请等待屏幕数量稳定后重试。"]; return; }
    DisplayProfile requested = profile < kProfileCount ? kProfiles[profile] : (DisplayProfile){"custom-hidpi", "Custom HiDPI", width*2, height*2, width, height, YES};
    NSString *error = nil;
    NSDictionary *physicalPlan = [self modePlanForDisplays:physical width:requested.logicalWidth height:requested.logicalHeight rate:rate error:&error];
    if (!physicalPlan) { [self showError:error]; return; }
    NSArray *virtualIDs = [self IDsForVirtualDisplays:self.displays];
    NSDictionary *previousModes = [self currentModesForDisplays:[physical arrayByAddingObjectsFromArray:virtualIDs]];
    if (!previousModes) { [self showError:@"无法保存当前显示模式，未更改设置。"]; return; }
    NSUInteger previousProfile = self.selectedProfile;
    unsigned int previousWidth = self.customLogicalWidth, previousHeight = self.customLogicalHeight;
    double previousRate = self.selectedRefreshRate;
    DisplayProfile previousDisplayProfile = [self currentProfile];
    // Existing screen objects and IDs must survive both success and rollback.
    NSArray *previousVirtuals = self.displays;
    BOOL kept = NO;
    self.applyingDisplaySettings = YES;
    ++self.displayChangeGeneration;
    self.displaySettingsIssue = nil;
    self.failedSettingsSignature = nil;
    self.selectedProfile = profile; self.customLogicalWidth = width; self.customLogicalHeight = height; self.selectedRefreshRate = rate;
    @try {
        BOOL advertised;
        if (!previousVirtuals.count && desired) {
            self.displays = [self createVirtualDisplays:desired];
            advertised = self.displays.count == desired;
            virtualIDs = [self IDsForVirtualDisplays:self.displays];
        } else advertised = [self advertiseVirtualDisplays:previousVirtuals profile:requested rate:rate];
        if (!advertised) { error = @"虚拟屏未接受该模式，已保留原显示器和原设置。"; }
        else {
            NSDictionary *virtualPlan = nil;
            for (NSUInteger attempt = 0; attempt < 10 && !virtualPlan; attempt++) {
                virtualPlan = [self modePlanForDisplays:virtualIDs width:requested.logicalWidth height:requested.logicalHeight rate:rate error:&error];
                if (!virtualPlan) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            if (virtualPlan) {
                NSMutableDictionary *plan = [physicalPlan mutableCopy]; [plan addEntriesFromDictionary:virtualPlan];
                if (![self configureModes:plan]) {
                    error = @"macOS 拒绝应用统一显示模式，原设置未保存。";
                }
                else {
                    if ([self modesAreCurrent:plan] && [self confirmUnifiedDisplaySettings] && [self topologyMatchesPhysical:physical virtualIDs:virtualIDs] && [self modesAreCurrent:plan]) {
                        self.unifiedSettingsEnabled = YES; self.suspendSavedSettings = NO;
                        [self persistUnifiedSettings]; kept = YES; error = nil;
                    } else error = @"未确认或实际显示模式不匹配，已恢复原设置。";
                }
            }
        }
        if (!kept) {
            BOOL restoredAdvertisement = [self advertiseVirtualDisplays:previousVirtuals profile:previousDisplayProfile rate:previousRate];
            BOOL restoredModes = [self restoreModes:previousModes];
            if (!restoredAdvertisement || !restoredModes) error = @"恢复原显示模式失败，请打开系统显示器设置检查。";
        }
    } @finally {
        if (!kept) {
            self.selectedProfile = previousProfile; self.customLogicalWidth = previousWidth;
            self.customLogicalHeight = previousHeight; self.selectedRefreshRate = previousRate;
            self.displays = [previousVirtuals mutableCopy];
            self.suspendSavedSettings = YES; // Queued display callbacks must not undo a cancellation.
        }
        self.applyingDisplaySettings = NO;
        self.lastSettingsApplyKept = kept;
        self.displaySettingsIssue = error;
        [self rebuildMenu];
    }
    if (error) [self showError:error];
    // A cable may have been unplugged during the modal confirmation. Reconcile
    // screen COUNT even after rollback, but suspend reapplying saved modes.
    [self scheduleDisplayReconciliation];
}

- (NSString *)settingsSignatureForDisplays:(NSArray<NSNumber *> *)ids profile:(DisplayProfile)p {
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%u/%u/%u/%u/%.2f", p.logicalWidth, p.logicalHeight,self.physicalPixelWidth,self.physicalPixelHeight, self.selectedRefreshRate];
    for (NSNumber *key in ids) {
        CGDirectDisplayID display = key.unsignedIntValue;
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
        [signature appendFormat:@"/%u:%u:%zu:%zu:%zu:%zu:%.2f", display, CGDisplayMirrorsDisplay(display),
            mode ? CGDisplayModeGetWidth(mode) : 0, mode ? CGDisplayModeGetHeight(mode) : 0,
            mode ? CGDisplayModeGetPixelWidth(mode) : 0, mode ? CGDisplayModeGetPixelHeight(mode) : 0,
            mode ? CGDisplayModeGetRefreshRate(mode) : 0];
        if (mode) CFRelease(mode);
    }
    return signature;
}

- (void)applySavedSettingsToActiveDisplays {
    if (self.virtualMirrorEnabled) return; // Mirror sources, not physical native modes, own the desktop.
    if (!self.unifiedSettingsEnabled || self.applyingDisplaySettings || self.suspendSavedSettings) return;
    NSArray *physical = [self physicalDisplayIDs];
    if (!physical) return;
    NSArray *ids = [physical arrayByAddingObjectsFromArray:[self IDsForVirtualDisplays:self.displays]];
    DisplayProfile p = [self currentProfile];
    NSString *signature = [self settingsSignatureForDisplays:ids profile:p];
    if ([signature isEqualToString:self.failedSettingsSignature]) return;
    NSString *error = nil;
    NSDictionary *plan = [self modePlanForDisplays:ids width:p.logicalWidth height:p.logicalHeight rate:self.selectedRefreshRate error:&error];
    BOOL pureNative = physical.count && !self.displays.count && ids.count == physical.count;
    if (!pureNative && plan && [self modesAreCurrent:plan]) { self.displaySettingsIssue = nil; return; }
    NSDictionary *previous = !pureNative && plan ? [self currentModesForDisplays:ids] : nil;
    BOOL ok = NO;
    self.applyingDisplaySettings = YES;
    if (pureNative) {
        // Public and hidden native modes share independent baseline/verification.
        // Mixed targets and virtual mirror sources retain their existing path.
        NSString *hiddenError = nil;
        ok = [self restoreHiddenNativeModesForDisplays:physical width:p.logicalWidth height:p.logicalHeight
            pixelWidth:(self.physicalPixelWidth ?: p.width) pixelHeight:(self.physicalPixelHeight ?: p.height)
            rate:self.selectedRefreshRate error:&hiddenError];
        if (!ok && hiddenError.length) error = error.length ? [NSString stringWithFormat:@"%@ %@",error,hiddenError] : hiddenError;
    } else if (plan && previous) {
        ok = [self configureModes:plan] && [self modesAreCurrent:plan];
        if (!ok && ![self restoreModes:previous]) error = @"恢复原显示模式失败，请检查系统显示器设置。";
    }
    self.applyingDisplaySettings = NO;
    self.failedSettingsSignature = ok ? nil : signature;
    self.displaySettingsIssue = ok ? nil : (error ?: @"系统未接受已保存的统一模式，保留当前屏幕，不自动镜像或降档。");
}

- (BOOL)restoreHiddenNativeModesForDisplays:(NSArray<NSNumber *> *)ids
    width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight
    rate:(double)rate error:(NSString **)error {
    return RDApplyHiddenNativeModes(ids,width,height,pixelWidth,pixelHeight,rate,error);
}

- (NSArray<NSNumber *> *)physicalDisplayIDs {
    CGDirectDisplayID ids[64]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return nil;
    NSMutableArray *physical = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        if (RDIsPhysicalDisplay(CGDisplayVendorNumber(ids[i]), CGDisplayModelNumber(ids[i]))) [physical addObject:@(ids[i])];
    }
    return physical;
}

- (NSUInteger)physicalDisplayCount {
    NSArray *physical = [self physicalDisplayIDs];
    return physical ? physical.count : NSNotFound;
}

- (void)displayWake:(NSNotification *)notification {
    (void)notification;
    self.failedSettingsSignature = nil;
    self.failedVirtualCreationSignature = nil;
    [self scheduleDisplayReconciliation];
}

- (void)scheduleDisplayReconciliation {
    if (!self.displayManagementEnabled) { self.displayReconciliationPending = NO; return; }
    if (self.applyingDisplaySettings || self.reconcilingDisplays) {
        // Merge callbacks received during a transaction. Drain once both busy
        // states clear; never start a periodic retry or re-enter configuration.
        self.displayReconciliationPending = YES;
        return;
    }
    self.displayReconciliationPending = NO;
    NSUInteger generation = ++self.displayChangeGeneration;
    [self enqueueDisplayReconciliationAfter:0.6 generation:generation];
}

- (void)enqueueDisplayReconciliationAfter:(NSTimeInterval)delay generation:(NSUInteger)generation {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performDisplayReconciliationForGeneration:generation];
    });
}

- (void)performDisplayReconciliationForGeneration:(NSUInteger)generation {
    if (generation != self.displayChangeGeneration) return;
    if (!self.displayManagementEnabled) { self.displayReconciliationPending = NO; return; }
    if (self.applyingDisplaySettings || self.reconcilingDisplays) { self.displayReconciliationPending = YES; return; }
    [self startDisplay:nil]; // Existing suspend, mirror, and saved-mode guards still apply.
}

- (void)togglePhysicalPriority:(id)sender {
    (void)sender;
    self.preferPhysicalDisplays = !self.preferPhysicalDisplays;
    [NSUserDefaults.standardUserDefaults setBool:self.preferPhysicalDisplays forKey:@"preferPhysicalDisplays"];
    self.displayManagementEnabled = YES;
    [self restartDisplaysIfActive];
}

- (void)selectDisplayCount:(NSMenuItem *)sender {
    self.selectedDisplayCount = (NSUInteger)sender.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)self.selectedDisplayCount forKey:@"displayCount"];
    [self restartDisplaysIfActive];
}

- (void)restartDisplaysIfActive {
    self.failedVirtualCreationSignature = nil;
    self.failedSettingsSignature = nil;
    [self restorePhysicalDisplay:nil];
    if (self.mirroredPhysicalDisplay || self.mirrorOriginals.count) return;
    BOOL wasActive = self.displayManagementEnabled;
    self.displays = nil;
    [self rebuildMenu];
    if (wasActive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.displayManagementEnabled) [self startDisplay:nil];
        });
    }
}

- (DisplayProfile)currentProfile {
    if (self.selectedProfile < kProfileCount) return kProfiles[self.selectedProfile];
    return (DisplayProfile){
        "custom-hidpi", "Custom HiDPI",
        self.customLogicalWidth * 2, self.customLogicalHeight * 2,
        self.customLogicalWidth, self.customLogicalHeight, YES
    };
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    if (self.applyingDisplaySettings) { self.displaySettingsIssue = message; return; }
    alert.messageText = @"无法应用显示设置";
    alert.informativeText = message ?: @"未知错误";
    [alert runModal];
}

- (void)startDisplay:(id)sender {
    if (self.applyingDisplaySettings || self.reconcilingDisplays) return;
    if (sender) { self.displayManagementEnabled = YES; self.failedVirtualCreationSignature = nil; self.failedSettingsSignature = nil; }
    if (!self.displayManagementEnabled) return;
    if (self.virtualMirrorEnabled) {
        if (sender) self.suspendSavedSettings=NO;
        if (self.suspendSavedSettings) { [self rebuildMenu]; return; }
        NSArray *physicalIDs=[self physicalDisplayIDs];
        if (!physicalIDs) return;
        NSArray *sources=[self IDsForVirtualDisplays:self.displays];
        NSDictionary *routes=[self mirrorRoutesForPhysical:physicalIDs sources:sources];
        DisplayProfile requested=[self currentProfile];
        if (sources.count==self.selectedDisplayCount && [self virtualSources:sources matchProfile:requested rate:self.selectedRefreshRate] && [self mirrorRoutesAreCurrent:routes] && [self physicalMirrorDisplays:physicalIDs matchRate:self.selectedRefreshRate]) { [self rebuildMenu]; return; }
        if (!sender && sources.count==self.selectedDisplayCount && [self mirrorRoutesAreCurrent:routes]) {
            // An external settings change must not trigger a mode fight with
            // System Settings. Only an explicit Apply resumes enforcement.
            self.suspendSavedSettings=YES;
            self.displaySettingsIssue=@"检测到显示模式已在系统中更改，已暂停自动覆盖；需要同步时请在统一显示设置中应用。";
            [self rebuildMenu]; return;
        }
        [self applyVirtualMirrorProfile:self.selectedProfile width:self.customLogicalWidth height:self.customLogicalHeight rate:self.selectedRefreshRate confirm:!self.mirrorConfigurationConfirmed];
        return;
    }
    NSUInteger physical = [self physicalDisplayCount];
    if (physical == NSNotFound) return; // Preserve the current topology if enumeration fails.
    NSUInteger desired = self.preferPhysicalDisplays
        ? (physical >= self.selectedDisplayCount ? 0 : self.selectedDisplayCount - physical)
        : self.selectedDisplayCount;
    DisplayProfile p = [self currentProfile];
    NSString *creationSignature = [NSString stringWithFormat:@"%lu/%lu/%u/%u/%.2f", (unsigned long)physical, (unsigned long)desired, p.width, p.height, self.selectedRefreshRate];
    if ([creationSignature isEqualToString:self.failedVirtualCreationSignature]) { [self rebuildMenu]; return; }
    if (self.displays.count == desired) { [self applySavedSettingsToActiveDisplays]; [self rebuildMenu]; return; }
    [self restorePhysicalDisplay:nil];
    if (self.mirroredPhysicalDisplay) return;
    self.displays = nil;
    if (desired == 0) {
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"正在使用实体屏幕"];
        [self applySavedSettingsToActiveDisplays]; [self rebuildMenu];
        return;
    }
    self.reconcilingDisplays = YES;
    @try {
        self.displays = [self createVirtualDisplays:desired];
        self.failedVirtualCreationSignature = self.displays ? nil : creationSignature;
    } @finally { self.reconcilingDisplays = NO; }
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:(self.displays.count ? @"display.2" : @"display") accessibilityDescription:@"Retina Dummy"];
    [self applySavedSettingsToActiveDisplays]; [self rebuildMenu];
    [self scheduleDisplayReconciliation];
}

- (NSMutableArray<CGVirtualDisplay *> *)createVirtualDisplays:(NSUInteger)desired {
    NSString *runtimeError = nil;
    if (!RuntimeSupportsVirtualDisplays(&runtimeError)) {
        [self showError:runtimeError];
        return nil;
    }

    DisplayProfile p = [self currentProfile];
    NSMutableArray<CGVirtualDisplay *> *created = [NSMutableArray array];

    for (NSUInteger displayIndex = 0; displayIndex < desired; displayIndex++) {
        CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.name = desired == 1
            ? @"Retina Dummy"
            : [NSString stringWithFormat:@"Retina Dummy %lu", (unsigned long)(displayIndex + 1)];
        // Advertise the supported maximum once so later settings can be applied
        // in-place without changing the virtual display ID.
        descriptor.maxPixelsWide = MAX(8192,p.width);
        descriptor.maxPixelsHigh = MAX(8192,p.height);
        descriptor.sizeInMillimeters = CGSizeMake(600, 600.0 * p.height / p.width);
        descriptor.redPrimary = CGPointMake(0.680, 0.320);
        descriptor.greenPrimary = CGPointMake(0.265, 0.690);
        descriptor.bluePrimary = CGPointMake(0.150, 0.060);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.vendorID = 0xB33F;
        unsigned int identity = (p.logicalWidth * 31u + p.logicalHeight * 17u) & 0x0FFFu;
        descriptor.productID = (unsigned int)(0x6000 + identity + displayIndex);
        descriptor.serialNum = (unsigned int)(displayIndex + 1);
        descriptor.queue = dispatch_get_main_queue();

        CGVirtualDisplay *display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!display) {
            [created removeAllObjects];
            [self showError:[NSString stringWithFormat:@"WindowServer 无法创建第 %lu 个虚拟显示器。", (unsigned long)(displayIndex + 1)]];
            return nil;
        }

        NSArray *modes=[self virtualModesForProfile:p rate:self.selectedRefreshRate];
        if (!modes.count) { [created removeAllObjects]; return nil; }

        CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.modes = modes;
        settings.hiDPI = 1;
        if (![display applySettings:settings]) {
            [created removeAllObjects];
            [self showError:[NSString stringWithFormat:@"macOS 未接受第 %lu 个显示器的 HiDPI 设置。", (unsigned long)(displayIndex + 1)]];
            return nil;
        }
        [created addObject:display];
    }

    return created;
}

- (BOOL)configurePhysicalDisplay:(CGDirectDisplayID)display mirror:(CGDirectDisplayID)source {
    CGDisplayConfigRef config = NULL;
    CGError result = CGBeginDisplayConfiguration(&config);
    if (result != kCGErrorSuccess) return NO;
    result = CGConfigureDisplayMirrorOfDisplay(config, display, source);
    if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    else CGCancelDisplayConfiguration(config);
    if (result != kCGErrorSuccess) { [self showError:[NSString stringWithFormat:@"macOS 未接受镜像设置（%d）。", result]]; return NO; }
    return YES;
}

- (void)restorePhysicalDisplay:(id)sender {
    (void)sender;
    if (self.mirrorOriginals.count && ![self restoreVirtualMirrorTargets]) { self.displaySettingsIssue=@"恢复实体屏未完成，保留虚拟画面；请勿退出软件。"; [self rebuildMenu]; return; }
    if (!self.mirroredPhysicalDisplay) return;
    if (!CGDisplayIsOnline(self.mirroredPhysicalDisplay) ||
        [self configurePhysicalDisplay:self.mirroredPhysicalDisplay mirror:
            (CGDisplayIsOnline(self.previousMirror) ? self.previousMirror : kCGNullDirectDisplay)]) {
        self.mirroredPhysicalDisplay = 0; self.previousMirror = 0;
    }
    [self rebuildMenu];
}

- (void)stopDisplay:(id)sender {
    if (sender) self.displayManagementEnabled = NO;
    [self restorePhysicalDisplay:nil];
    if (self.mirroredPhysicalDisplay || self.mirrorOriginals.count) return;
    self.displays = nil;
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Retina Dummy"];
    [self rebuildMenu];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (self.applyingDisplaySettings) {
        [NSApp abortModal]; // Return through the same rollback path before allowing exit.
        return NSTerminateCancel;
    }
    [self restorePhysicalDisplay:nil];
    if (self.mirroredPhysicalDisplay || self.mirrorOriginals.count) return NSTerminateCancel;
    self.displayManagementEnabled = NO;
    ++self.displayChangeGeneration;
    CGDisplayRemoveReconfigurationCallback(RetinaDisplayChanged, (__bridge void *)self);
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    self.displays = nil;
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    return NSTerminateNow;
}
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
