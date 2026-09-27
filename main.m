#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>
#import <objc/runtime.h>
#import <math.h>

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

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMutableArray<CGVirtualDisplay *> *displays;
@property(nonatomic) NSUInteger selectedProfile;
@property(nonatomic) NSUInteger selectedDisplayCount;
@property(nonatomic) unsigned int customLogicalWidth;
@property(nonatomic) unsigned int customLogicalHeight;
@property(nonatomic) double selectedRefreshRate;
@property(nonatomic, strong) NSWindow *aboutWindow;
- (DisplayProfile)currentProfile;
- (void)restartDisplaysIfActive;
- (void)showResolutionPicker:(id)sender;
- (void)restoreLoginItemIfRequested;
@end

@implementation AppDelegate

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
    double savedRefreshRate = [[NSUserDefaults standardUserDefaults] doubleForKey:@"refreshRate"];
    const double supportedRates[] = {30, 60, 75, 90, 120, 144};
    self.selectedRefreshRate = 60;
    for (NSUInteger i = 0; i < sizeof(supportedRates) / sizeof(supportedRates[0]); i++) {
        if (fabs(savedRefreshRate - supportedRates[i]) < 0.1) self.selectedRefreshRate = supportedRates[i];
    }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Retina Dummy"];
    self.statusItem.button.toolTip = @"Retina Dummy 虚拟显示器";
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--enable-login-item"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"launchAtLoginRequested"];
    }
    [self restoreLoginItemIfRequested];
    [self rebuildMenu];
    [self startDisplay:nil];
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    BOOL active = self.displays.count > 0;
    NSString *headerTitle = active
        ? [NSString stringWithFormat:@"%lu 个虚拟显示器已开启", (unsigned long)self.displays.count]
        : @"虚拟显示器已关闭";
    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:headerTitle action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];
    [menu addItem:[NSMenuItem separatorItem]];

    DisplayProfile currentProfile = [self currentProfile];
    NSMenuItem *resolutionItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"HiDPI 设置…   %u × %u @ %.0fHz", currentProfile.logicalWidth, currentProfile.logicalHeight, self.selectedRefreshRate]
               action:@selector(showResolutionPicker:)
        keyEquivalent:@""];
    resolutionItem.target = self;
    [menu addItem:resolutionItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *countItem = [[NSMenuItem alloc] initWithTitle:@"虚拟显示器数量" action:nil keyEquivalent:@""];
    NSMenu *countMenu = [[NSMenu alloc] initWithTitle:@"虚拟显示器数量"];
    for (NSUInteger count = 1; count <= 3; count++) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithFormat:@"%lu 个显示器", (unsigned long)count]
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

    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:(active ? @"关闭虚拟显示器" : @"开启虚拟显示器") action:(active ? @selector(stopDisplay:) : @selector(startDisplay:)) keyEquivalent:@""];
    toggle.target = self;
    [menu addItem:toggle];
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"登录时自动启动" action:@selector(toggleLoginItem:) keyEquivalent:@""];
    login.target = self;
    login.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff);
    [menu addItem:login];
    [menu addItem:[NSMenuItem separatorItem]];

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
    self.selectedProfile = (NSUInteger)sender.tag;
    [[NSUserDefaults standardUserDefaults] setObject:@(kProfiles[self.selectedProfile].key) forKey:@"profile"];
    [self restartDisplaysIfActive];
}

- (void)showResolutionPicker:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"HiDPI 显示设置";
    alert.informativeText = @"选择逻辑桌面尺寸和刷新率，内部将以 2× 分辨率渲染。";
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
    const NSInteger rates[] = {30, 60, 75, 90, 120, 144};
    for (NSUInteger i = 0; i < sizeof(rates) / sizeof(rates[0]); i++) {
        [refreshPopup addItemWithTitle:[NSString stringWithFormat:@"%ld Hz", (long)rates[i]]];
        refreshPopup.lastItem.tag = rates[i];
    }
    [refreshPopup selectItemWithTag:(NSInteger)self.selectedRefreshRate];
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

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.selectedRefreshRate = (double)refreshPopup.selectedItem.tag;
    [[NSUserDefaults standardUserDefaults] setDouble:self.selectedRefreshRate forKey:@"refreshRate"];
    NSInteger selection = popup.selectedItem.tag;
    if (selection == -100) {
        [self showCustomResolution:nil];
        return;
    }
    self.selectedProfile = (NSUInteger)selection;
    [[NSUserDefaults standardUserDefaults] setObject:@(kProfiles[self.selectedProfile].key) forKey:@"profile"];
    [self restartDisplaysIfActive];
}

- (void)showCustomResolution:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"自定义 HiDPI 分辨率";
    alert.informativeText = @"输入逻辑桌面的宽度和高度。实际渲染分辨率为输入值的 2 倍。";
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"取消"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 72)];
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

    self.customLogicalWidth = (unsigned int)width;
    self.customLogicalHeight = (unsigned int)height;
    self.selectedProfile = kProfileCount;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@"custom-hidpi" forKey:@"profile"];
    [defaults setInteger:width forKey:@"customLogicalWidth"];
    [defaults setInteger:height forKey:@"customLogicalHeight"];
    [self restartDisplaysIfActive];
}

- (void)selectDisplayCount:(NSMenuItem *)sender {
    self.selectedDisplayCount = (NSUInteger)sender.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)self.selectedDisplayCount forKey:@"displayCount"];
    [self restartDisplaysIfActive];
}

- (void)restartDisplaysIfActive {
    BOOL wasActive = self.displays.count > 0;
    self.displays = nil;
    [self rebuildMenu];
    if (wasActive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startDisplay:nil];
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
    alert.messageText = @"无法创建虚拟显示器";
    alert.informativeText = message ?: @"未知错误";
    [alert runModal];
}

- (void)startDisplay:(id)sender {
    (void)sender;
    if (self.displays.count > 0) return;
    NSString *runtimeError = nil;
    if (!RuntimeSupportsVirtualDisplays(&runtimeError)) {
        [self showError:runtimeError];
        return;
    }

    DisplayProfile p = [self currentProfile];
    NSMutableArray<CGVirtualDisplay *> *created = [NSMutableArray array];
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");

    for (NSUInteger displayIndex = 0; displayIndex < self.selectedDisplayCount; displayIndex++) {
        CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.name = self.selectedDisplayCount == 1
            ? @"Retina Dummy"
            : [NSString stringWithFormat:@"Retina Dummy %lu", (unsigned long)(displayIndex + 1)];
        descriptor.maxPixelsWide = p.width;
        descriptor.maxPixelsHigh = p.height;
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
            return;
        }

        NSMutableArray *modes = [NSMutableArray array];
        [modes addObject:[[modeClass alloc] initWithWidth:p.width height:p.height refreshRate:self.selectedRefreshRate]];
        const double scales[] = {0.90, 0.80, 0.75, 2.0 / 3.0};
        for (NSUInteger i = 0; i < sizeof(scales) / sizeof(scales[0]); i++) {
            unsigned int width = ((unsigned int)(p.width * scales[i]) / 2) * 2;
            unsigned int height = ((unsigned int)(p.height * scales[i]) / 2) * 2;
            [modes addObject:[[modeClass alloc] initWithWidth:width height:height refreshRate:self.selectedRefreshRate]];
        }

        CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.modes = modes;
        settings.hiDPI = 1;
        if (![display applySettings:settings]) {
            [created removeAllObjects];
            [self showError:[NSString stringWithFormat:@"macOS 未接受第 %lu 个显示器的 HiDPI 设置。", (unsigned long)(displayIndex + 1)]];
            return;
        }
        [created addObject:display];
    }

    self.displays = created;
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display.2" accessibilityDescription:@"Retina Dummy 已开启"];
    [self rebuildMenu];
}

- (void)stopDisplay:(id)sender {
    (void)sender;
    self.displays = nil;
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Retina Dummy"];
    [self rebuildMenu];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    self.displays = nil;
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
