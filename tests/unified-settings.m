#define main RetinaAppMain
#import "../main.m"
#undef main

@interface UnifiedProbe : AppDelegate
@property NSArray *physicalIDs;
@property NSNumber *unsupported;
@property BOOL failVirtual;
@property BOOL failCommit;
@property BOOL failVerification;
@property BOOL keep;
@property NSUInteger creations;
@property NSUInteger commits;
@property NSUInteger rollbacks;
@property NSUInteger saves;
@property NSDictionary *activePlan;
@property NSDictionary *committedPlan;
@property NSString *lastError;
@property NSUInteger advertisements;
@property BOOL failAdvertisement;
@property BOOL topologyChanged;
@property BOOL failRestoringAdvertisement;
@property NSUInteger reconciliations;
@property NSUInteger queuedReconciliationGeneration;
@property NSUInteger reconciliationStarts;
@property NSUInteger hiddenNativeAttempts;
@property NSUInteger nativeRecoveryAttempts;
@property BOOL hiddenNativeSucceeds;
@property NSDictionary *hiddenNativeRequest;
@end
@implementation UnifiedProbe
- (instancetype)init { if ((self = [super init])) {
    self.physicalIDs = @[@1]; self.keep = YES;
    self.displayManagementEnabled = YES; self.preferPhysicalDisplays = YES;
    self.selectedDisplayCount = 1; self.selectedProfile = 2;
    self.selectedRefreshRate = 60; self.customLogicalWidth = 2000; self.customLogicalHeight = 1200;
    self.displays = [NSMutableArray array];
} return self; }
- (NSArray *)physicalDisplayIDs { return self.physicalIDs; }
- (NSDictionary *)modePlanForDisplays:(NSArray *)ids width:(unsigned int)width height:(unsigned int)height rate:(double)rate error:(NSString **)error {
    NSMutableDictionary *plan = [NSMutableDictionary dictionary];
    for (NSNumber *key in ids) {
        if ([key isEqual:self.unsupported]) { if (error) *error = @"unsupported"; return nil; }
        plan[key] = [NSString stringWithFormat:@"%u/%u/%.0f", width, height, rate];
    }
    return plan;
}
- (NSDictionary *)currentModesForDisplays:(NSArray *)ids {
    NSMutableDictionary *modes = [NSMutableDictionary dictionary];
    for (NSNumber *key in ids) modes[key] = @"original";
    return modes;
}
- (NSMutableArray *)createVirtualDisplays:(NSUInteger)desired {
    self.creations++; if (self.failVirtual) return nil;
    NSMutableArray *screens = [NSMutableArray array];
    for (NSUInteger i=0; i<desired; i++) [screens addObject:@(100+i)];
    return screens;
}
- (NSArray *)IDsForVirtualDisplays:(NSArray *)displays { return displays ?: @[]; }
- (BOOL)advertiseVirtualDisplays:(NSArray *)displays profile:(DisplayProfile)p rate:(double)rate {
    (void)displays; (void)p; (void)rate;
    self.advertisements++;
    return !((self.failAdvertisement && self.advertisements==1) || (self.failRestoringAdvertisement && self.advertisements==2));
}
- (BOOL)topologyMatchesPhysical:(NSArray *)physical virtualIDs:(NSArray *)virtualIDs {
    return !self.topologyChanged && [self.physicalIDs isEqual:physical] && [[self IDsForVirtualDisplays:self.displays] isEqual:virtualIDs];
}
- (BOOL)configureModes:(NSDictionary *)plan {
    self.commits++; self.committedPlan = plan;
    if (self.failCommit) return NO;
    self.activePlan = plan; return YES;
}
- (BOOL)modesAreCurrent:(NSDictionary *)plan { return !self.failVerification && [self.activePlan isEqual:plan]; }
- (BOOL)restoreModes:(NSDictionary *)previous { self.rollbacks++; self.activePlan=previous; return YES; }
- (BOOL)restoreHiddenNativeModesForDisplays:(NSArray *)ids width:(unsigned int)width height:(unsigned int)height
    pixelWidth:(unsigned int)pixelWidth pixelHeight:(unsigned int)pixelHeight rate:(double)rate error:(NSString **)error {
    assert(self.applyingDisplaySettings && !self.virtualMirrorEnabled);
    self.nativeRecoveryAttempts++;
    if (!self.unsupported) {
        NSDictionary *plan=[self modePlanForDisplays:ids width:width height:height rate:rate error:error];
        if ([self modesAreCurrent:plan]) return YES;
        BOOL ok=[self configureModes:plan] && [self modesAreCurrent:plan];
        if (!ok) [self restoreModes:[self currentModesForDisplays:ids]];
        return ok;
    }
    self.hiddenNativeAttempts++;
    self.hiddenNativeRequest=@{@"ids":ids,@"width":@(width),@"height":@(height),@"pixelWidth":@(pixelWidth),@"pixelHeight":@(pixelHeight),@"rate":@(rate)};
    if (!self.hiddenNativeSucceeds && error) *error=@"hidden-native recovery failed; original mode restored";
    return self.hiddenNativeSucceeds;
}
- (BOOL)confirmUnifiedDisplaySettings { assert(self.applyingDisplaySettings); return self.keep; }
- (void)persistUnifiedSettings { self.saves++; }
- (void)rebuildMenu {}
- (void)showError:(NSString *)error { self.lastError=error; }
- (void)enqueueDisplayReconciliationAfter:(NSTimeInterval)delay generation:(NSUInteger)generation {
    assert(delay>=0.6); self.reconciliations++; self.queuedReconciliationGeneration=generation;
} // Test queued work explicitly; never dispatch a real display configuration.
- (void)startDisplay:(id)sender { self.reconciliationStarts++; [super startDisplay:sender]; }
@end

static void apply(UnifiedProbe *p) { [p applyUnifiedSettingsProfile:3 width:2000 height:1200 rate:60]; }
int main(void) { @autoreleasepool {
    assert(RDIsPhysicalDisplay(0x1ee4, 0x9161));
    assert(!RDIsPhysicalDisplay(0xB33F, 1));
    assert(!RDIsPhysicalDisplay(0x756e6b6e, 0x76697274));
    assert(RDMatchesHiDPI(1920,1080,3840,2160,59.94,1920,1080,60));
    assert(!RDMatchesHiDPI(1920,1080,1920,1080,60,1920,1080,60));
    assert(!RDMatchesHiDPI(1920,1080,3840,2160,165,1920,1080,60));
    assert(!RDMatchesHiDPI(1920,1080,3840,2160,0,1920,1080,60));
    assert(!RDMatchesHiDPI(1920,1080,3840,2160,NAN,1920,1080,60));
    assert(!RDMatchesHiDPI(1920,1080,3840,2160,60,2048,1152,60));
    UnifiedProbe *p=[UnifiedProbe new]; apply(p);
    assert(p.saves==1 && p.commits==1 && p.creations==0 && p.displays.count==0 && p.unifiedSettingsEnabled);
    assert([p.committedPlan[@1] isEqual:@"2048/1152/60"]);
    p=[UnifiedProbe new]; p.physicalIDs=@[@1,@2]; p.selectedDisplayCount=3; apply(p);
    assert(p.displays.count==1 && p.committedPlan.count==3 && p.saves==1);
    assert([p.committedPlan[@1] isEqual:p.committedPlan[@100]]);
    p=[UnifiedProbe new]; p.physicalIDs=@[@1]; p.selectedDisplayCount=2; p.displays=[@[@100] mutableCopy]; apply(p);
    assert(p.creations==0 && p.saves==1 && [p.displays isEqual:@[@100]]); // Preserve IDs on success.
    p=[UnifiedProbe new]; p.physicalIDs=@[]; p.selectedDisplayCount=2; apply(p);
    assert(p.displays.count==2 && p.committedPlan.count==2 && p.saves==1);
    p=[UnifiedProbe new]; p.physicalIDs=@[@1,@2]; p.unsupported=@2; apply(p);
    assert(p.commits==0 && p.creations==0 && p.saves==0 && p.selectedProfile==2);
    p=[UnifiedProbe new]; p.selectedDisplayCount=2; p.failVirtual=YES; apply(p);
    assert(p.commits==0 && p.saves==0 && p.selectedProfile==2 && !p.applyingDisplaySettings);
    p=[UnifiedProbe new]; p.failCommit=YES; apply(p);
    assert(p.rollbacks==1 && p.saves==0 && p.selectedProfile==2);
    p=[UnifiedProbe new]; p.failVerification=YES; apply(p);
    assert(p.rollbacks==1 && p.saves==0 && p.selectedProfile==2);
    p=[UnifiedProbe new]; p.keep=NO; p.displays=[@[@200] mutableCopy]; p.selectedDisplayCount=2; apply(p);
    assert(p.rollbacks==1 && p.saves==0 && [p.displays isEqual:@[@200]] && p.selectedProfile==2);
    assert(p.creations==0 && p.suspendSavedSettings);
    p.unifiedSettingsEnabled=YES; NSUInteger commits=p.commits;
    [p applySavedSettingsToActiveDisplays]; assert(p.commits==commits); // Cancellation cannot be undone by callbacks.
    p=[UnifiedProbe new]; p.selectedDisplayCount=2; p.displays=[@[@100] mutableCopy]; p.failAdvertisement=YES; apply(p);
    assert(p.saves==0 && p.rollbacks==1 && p.advertisements==2 && [p.displays isEqual:@[@100]]);
    p=[UnifiedProbe new]; p.topologyChanged=YES; apply(p); assert(p.saves==0 && p.rollbacks==1);
    assert(p.reconciliations==1 && p.suspendSavedSettings);
    p=[UnifiedProbe new]; p.keep=NO; p.failRestoringAdvertisement=YES; apply(p);
    assert(p.rollbacks==1 && p.saves==0); // Restore physical modes even if advertisement rollback fails.
    p=[UnifiedProbe new]; p.physicalIDs=nil; apply(p); assert(p.commits==0 && p.saves==0);
    p=[UnifiedProbe new]; p.displayManagementEnabled=NO; apply(p); assert(p.commits==0 && p.saves==0);
    p=[UnifiedProbe new]; p.applyingDisplaySettings=YES; apply(p); assert(p.commits==0);
    p=[UnifiedProbe new]; p.mirroredPhysicalDisplay=1; apply(p); assert(p.commits==0);
    p=[UnifiedProbe new]; [p applyUnifiedSettingsProfile:kProfileCount width:640 height:480 rate:60];
    assert([p.committedPlan[@1] isEqual:@"640/480/60"] && p.saves==1);
    p=[UnifiedProbe new]; [p applyUnifiedSettingsProfile:kProfileCount width:1 height:480 rate:60]; assert(p.commits==0);
    p=[UnifiedProbe new]; [p applySavedSettingsToActiveDisplays]; assert(p.commits==0); // Safe upgrade migration.
    p.unifiedSettingsEnabled=YES; [p applySavedSettingsToActiveDisplays]; assert(p.commits==1 && p.nativeRecoveryAttempts==1);
    [p applySavedSettingsToActiveDisplays]; assert(p.commits==1 && p.nativeRecoveryAttempts==2); // Fresh verification, no mode-change loop.
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.unsupported=@1;
    [p applySavedSettingsToActiveDisplays]; assert(p.failedSettingsSignature && p.commits==0 && p.hiddenNativeAttempts==1);
    assert([p.displaySettingsIssue containsString:@"original mode restored"]);
    assert([p.displaySettingsIssue containsString:@"unsupported"]); // Preserve the public display/format diagnostic too.
    [p applySavedSettingsToActiveDisplays]; assert(p.commits==0 && p.hiddenNativeAttempts==1);
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.unsupported=@1; p.hiddenNativeSucceeds=YES;
    p.selectedProfile=3; p.selectedRefreshRate=165; p.physicalPixelWidth=4096; p.physicalPixelHeight=2304;
    [p applySavedSettingsToActiveDisplays];
    assert(p.hiddenNativeAttempts==1 && p.commits==0 && !p.failedSettingsSignature && !p.displaySettingsIssue && p.saves==0);
    assert([p.hiddenNativeRequest[@"width"] unsignedIntValue]==2048 && [p.hiddenNativeRequest[@"height"] unsignedIntValue]==1152);
    assert([p.hiddenNativeRequest[@"pixelWidth"] unsignedIntValue]==4096 && [p.hiddenNativeRequest[@"pixelHeight"] unsignedIntValue]==2304 && [p.hiddenNativeRequest[@"rate"] doubleValue]==165);
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.unsupported=@1; p.displays=[@[@100] mutableCopy];
    [p applySavedSettingsToActiveDisplays]; assert(p.hiddenNativeAttempts==0 && p.nativeRecoveryAttempts==0 && p.commits==0);
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.unsupported=@1; p.virtualMirrorEnabled=YES;
    [p applySavedSettingsToActiveDisplays]; assert(p.hiddenNativeAttempts==0 && p.nativeRecoveryAttempts==0 && p.commits==0);
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.hiddenNativeSucceeds=YES;
    [p applySavedSettingsToActiveDisplays]; assert(p.hiddenNativeAttempts==0 && p.nativeRecoveryAttempts==1 && p.commits==1); // Public modes share the recovery engine.
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.failCommit=YES;
    [p applySavedSettingsToActiveDisplays]; assert(p.rollbacks==1 && p.failedSettingsSignature);
    commits=p.commits; [p applySavedSettingsToActiveDisplays]; assert(p.commits==commits);
    [p startDisplay:[NSObject new]]; assert(p.commits==commits+1); // Explicit retry clears the failure cache.
    p=[UnifiedProbe new]; p.applyingDisplaySettings=YES;
    for(NSUInteger i=0;i<100;i++)[p scheduleDisplayReconciliation];
    assert(p.displayReconciliationPending && p.reconciliations==0 && p.reconciliationStarts==0);
    p.reconcilingDisplays=YES; p.applyingDisplaySettings=NO;
    assert(p.displayReconciliationPending && p.reconciliations==0); // Both busy states must finish.
    p.reconcilingDisplays=NO;
    assert(!p.displayReconciliationPending && p.reconciliations==1 && p.reconciliationStarts==0);
    [p performDisplayReconciliationForGeneration:p.queuedReconciliationGeneration];
    assert(p.reconciliationStarts==1 && p.reconciliations==1 && p.commits==0);
    p=[UnifiedProbe new]; [p scheduleDisplayReconciliation]; NSUInteger queued=p.queuedReconciliationGeneration;
    p.applyingDisplaySettings=YES; [p performDisplayReconciliationForGeneration:queued];
    assert(p.displayReconciliationPending && p.reconciliationStarts==0);
    p.applyingDisplaySettings=NO; assert(p.reconciliations==2 && !p.displayReconciliationPending);
    [p performDisplayReconciliationForGeneration:queued]; assert(p.reconciliationStarts==0); // Superseded work stays cancelled.
    [p performDisplayReconciliationForGeneration:p.queuedReconciliationGeneration]; assert(p.reconciliationStarts==1);
    p=[UnifiedProbe new]; p.applyingDisplaySettings=YES; [p scheduleDisplayReconciliation];
    p.displayManagementEnabled=NO; p.applyingDisplaySettings=NO;
    assert(!p.displayReconciliationPending && p.reconciliations==0); // Pause/quit discards pending work.
    p=[UnifiedProbe new]; p.unifiedSettingsEnabled=YES; p.suspendSavedSettings=YES;
    p.applyingDisplaySettings=YES; [p scheduleDisplayReconciliation]; p.applyingDisplaySettings=NO;
    [p performDisplayReconciliationForGeneration:p.queuedReconciliationGeneration];
    assert(p.commits==0 && p.nativeRecoveryAttempts==0 && p.suspendSavedSettings); // Never override user cancellation.
    puts("PASS: exact HiDPI/rate matching, physical/system-virtual classification, shared physical+virtual plan, 1/2/3-screen policy, unsupported-mode preflight, creation/commit/verification failure, cancel/timeout rollback path, preference atomicity, upgrade migration, reconciliation idempotence");
} }
