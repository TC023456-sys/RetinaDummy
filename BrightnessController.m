#import "BrightnessController.h"
#include <signal.h>
@interface BrightnessController ()
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, copy) NSString *displayUUID;
@property(nonatomic, strong) NSSlider *slider;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *refresh;
@property(nonatomic) NSUInteger generation;
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
- (void)showForDisplay:(CGDirectDisplayID)displayID name:(NSString *)name {
    self.displayID = displayID;
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    self.displayUUID = uuid ? CFBridgingRelease(CFUUIDCreateString(NULL, uuid)) : @"";
    if (uuid) CFRelease(uuid);
    self.window.title = [NSString stringWithFormat:@"%@ · 实体亮度",name];
    [self.window center];
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshClicked:nil];
}
- (void)refreshClicked:(id)sender { (void)sender; [self runCommand:@"--probe" value:nil]; }
- (void)sliderChanged:(NSSlider *)sender { [self runCommand:@"--set" value:@(sender.doubleValue)]; }
- (void)runCommand:(NSString *)mode value:(NSNumber *)value {
    NSUInteger generation = ++self.generation;
    CGDirectDisplayID displayID = self.displayID;
    NSString *uuid = self.displayUUID;
    self.slider.enabled = NO; self.refresh.enabled = NO;
    self.status.stringValue = value ? @"正在调节并读取确认…" : @"正在读取硬件亮度…";
#if !defined(__arm64__)
    self.status.stringValue = @"当前硬件亮度功能支持 Apple 芯片 Mac 的 DDC/CI 外接显示器，暂不支持 Intel Mac。";
    self.refresh.enabled = YES;
    return;
#endif
    NSURL *helper = [NSBundle.mainBundle URLForResource:@"RetinaBrightness" withExtension:nil];
    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableArray *args = [NSMutableArray arrayWithArray:@[mode,[@(displayID) stringValue],uuid]];
            if (value) [args addObject:value.stringValue];
            NSTask *task = [[NSTask alloc] init]; task.executableURL = helper; task.arguments = args;
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
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.generation) return;
                self.refresh.enabled = YES;
                NSNumber *percent = result[@"percent"];
                if ([percent isKindOfClass:NSNumber.class] && isfinite(percent.doubleValue) && percent.doubleValue >= 0 && percent.doubleValue <= 100 && [result[@"displayID"] unsignedIntValue] == displayID) {
                    self.slider.doubleValue = percent.doubleValue; self.slider.enabled = YES;
                    self.status.stringValue = [NSString stringWithFormat:@"硬件亮度：%.0f%% · 已从显示器读取确认",percent.doubleValue];
                } else {
                    self.status.stringValue = [result[@"error"] isKindOfClass:NSString.class] ? result[@"error"] : @"显示器不支持当前连接的硬件亮度调节。";
                }
            });
        }
    });
}
@end
