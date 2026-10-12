#import "BrightnessController.h"
#include <signal.h>
@interface BrightnessController ()
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, copy) NSString *displayUUID;
@property(nonatomic, strong) NSSlider *slider;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *refresh;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL busy;
@property(nonatomic, strong) NSView *menuView;
@property(nonatomic, strong) NSSlider *menuSlider;
@property(nonatomic, strong) NSTextField *menuTitle;
@property(nonatomic, strong) NSTextField *menuStatus;
@property(nonatomic, strong) NSButton *menuRefresh;
@property(nonatomic, strong) dispatch_queue_t workQueue;
@end
@implementation BrightnessController
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,460,220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.releasedWhenClosed = NO;
        self.workQueue = dispatch_queue_create("local.liang.RetinaDummy.brightness", DISPATCH_QUEUE_SERIAL);
        NSTextField *title = [NSTextField labelWithString:@"实体显示器亮度"];
        title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
        self.slider = [NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(sliderChanged:)];
        self.slider.continuous = NO;
        self.status = [NSTextField wrappingLabelWithString:@"正在读取…"];
        self.status.selectable = YES;
        self.refresh = [NSButton buttonWithTitle:@"重新读取" target:self action:@selector(refreshClicked:)];
        NSStackView *stack = [NSStackView stackViewWithViews:@[title,self.slider,self.status,self.refresh]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:24],
            [stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-24],
            [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24],
            [self.slider.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [self.status.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
        ]];
    }
    return self;
}
- (void)prepareForDisplay:(CGDirectDisplayID)displayID {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    NSString *identity = uuid ? CFBridgingRelease(CFUUIDCreateString(NULL, uuid)) : @"";
    if (uuid) CFRelease(uuid);
    if (self.displayID != displayID || ![self.displayUUID isEqualToString:identity]) {
        ++self.generation;
        self.busy = NO;
        self.slider.enabled = NO;
        self.menuSlider.enabled = NO;
    }
    self.displayID = displayID;
    self.displayUUID = identity;
}
- (NSView *)menuViewForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name {
    [self prepareForDisplay:displayID];
    if (!self.menuView) {
        self.menuView = [[NSView alloc] initWithFrame:NSMakeRect(0,0,320,144)];
        self.menuTitle = [NSTextField labelWithString:@""];
        self.menuTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        self.menuTitle.frame = NSMakeRect(16,116,288,20);
        self.menuSlider = [NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(sliderChanged:)];
        self.menuSlider.continuous = NO;
        self.menuSlider.frame = NSMakeRect(16,86,288,24);
        self.menuSlider.accessibilityLabel = [name stringByAppendingString:@" 实体亮度"];
        self.menuStatus = [NSTextField wrappingLabelWithString:@"正在读取硬件亮度…"];
        self.menuStatus.font = [NSFont systemFontOfSize:11];
        self.menuStatus.textColor = NSColor.secondaryLabelColor;
        self.menuStatus.frame = NSMakeRect(16,38,288,42);
        self.menuRefresh = [NSButton buttonWithTitle:@"重新读取" target:self action:@selector(refreshClicked:)];
        self.menuRefresh.bezelStyle = NSBezelStyleRounded;
        self.menuRefresh.frame = NSMakeRect(12,6,100,28);
        for (NSView *view in @[self.menuTitle,self.menuSlider,self.menuStatus,self.menuRefresh]) [self.menuView addSubview:view];
    }
    self.menuTitle.stringValue = [name stringByAppendingString:@" · 亮度"];
    [self refreshClicked:nil];
    return self.menuView;
}
- (void)setStatusMessage:(NSString *)message {
    self.status.stringValue = message;
    self.menuStatus.stringValue = message;
    self.menuStatus.toolTip = message;
}
- (void)showForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name {
    [self prepareForDisplay:displayID];
    self.window.title = [NSString stringWithFormat:@"%@ · 实体亮度",name];
    [self.window center];
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshClicked:nil];
}
- (void)refreshClicked:(id)sender { (void)sender; [self runCommand:@"--probe" value:nil]; }
- (void)sliderChanged:(NSSlider *)sender { [self runCommand:@"--set" value:@(sender.doubleValue)]; }
- (void)runCommand:(NSString *)mode value:(NSNumber *)value {
    if (self.busy) return;
    self.busy = YES;
    NSUInteger generation = ++self.generation;
    CGDirectDisplayID displayID = self.displayID;
    NSString *uuid = self.displayUUID;
    self.slider.enabled = NO; self.refresh.enabled = NO;
    self.menuSlider.enabled = NO; self.menuRefresh.enabled = NO;
    [self setStatusMessage:value ? @"正在调节并读取确认…" : @"正在读取硬件亮度…"];
#if !defined(__arm64__)
    [self setStatusMessage:@"当前硬件亮度功能支持 Apple 芯片 Mac，暂不支持 Intel Mac。"];
    self.refresh.enabled = YES; self.menuRefresh.enabled = YES; self.busy = NO;
    return;
#endif
    NSURL *helper = [NSBundle.mainBundle URLForResource:@"RetinaBrightness" withExtension:nil];
    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableArray *args = [NSMutableArray arrayWithArray:@[mode,[@(displayID) stringValue],uuid]];
            if (value) [args addObject:value.stringValue];
            NSTask *task = [[NSTask alloc] init];
            if (helper) task.executableURL = helper;
            task.arguments = args;
            NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = NSFileHandle.fileHandleWithNullDevice;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            task.terminationHandler = ^(NSTask *ended) { (void)ended; dispatch_semaphore_signal(done); };
            NSError *error = nil;
            NSDictionary *result = nil;
            BOOL launched = helper && [task launchAndReturnError:&error];
            if (launched) {
                BOOL timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 4*NSEC_PER_SEC)) != 0;
                if (timedOut && task.running) { [task terminate]; if (task.running) kill(task.processIdentifier,SIGKILL); }
                [task waitUntilExit];
                NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
                id parsed = data.length < 8192 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                if (timedOut) result = @{@"error":@"显示器响应超时，请检查 DDC/CI 和连接后重试。"};
                else if ([parsed isKindOfClass:NSDictionary.class]) result = parsed;
            }
            if (!result) result = @{@"error": error.localizedDescription ?: @"无法读取显示器硬件亮度。"};
            // Menu tracking uses a nested run loop. Deliver results in common
            // modes so the visible slider updates without closing the menu.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
                if (generation != self.generation) return;
                self.busy = NO;
                self.refresh.enabled = YES; self.menuRefresh.enabled = YES;
                NSNumber *percent = result[@"percent"];
                if ([percent isKindOfClass:NSNumber.class] && isfinite(percent.doubleValue) && percent.doubleValue >= 0 && percent.doubleValue <= 100 && [result[@"displayID"] unsignedIntValue] == displayID) {
                    self.slider.doubleValue = percent.doubleValue; self.slider.enabled = YES;
                    self.menuSlider.doubleValue = percent.doubleValue; self.menuSlider.enabled = YES;
                    [self setStatusMessage:[NSString stringWithFormat:@"硬件亮度：%.0f%% · 已读取确认",percent.doubleValue]];
                } else {
                    [self setStatusMessage:[result[@"error"] isKindOfClass:NSString.class] ? result[@"error"] : @"显示器不支持当前连接的硬件亮度调节。"];
                }
            });
            CFRunLoopWakeUp(CFRunLoopGetMain());
        }
    });
}
@end
