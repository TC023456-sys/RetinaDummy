// Mock backend only: never creates a real virtual screen or changes a mode.
#define main RetinaAppMain
#import "../main.m"
#undef main
@interface MirrorProbe : AppDelegate
@property NSArray *physicalIDs;
@property NSMutableDictionary *routes;
@property NSUInteger creations;
@property NSUInteger saves;
@property NSUInteger commits;
@property NSUInteger restores;
@property NSUInteger reconciliations;
@property BOOL keep;
@property BOOL failCreation;
@property BOOL failMirror;
@property BOOL failRestore;
@property BOOL failVerify;
@property BOOL topologyChanged;
@property BOOL unsupportedRate;
@property BOOL failPhysicalRate;
@property double physicalRate;
@property NSUInteger advertisements;
@property unsigned int catalogWidth;
@property unsigned int activeWidth;
@property double activeRate;
@property NSString *lastError;
@end
@implementation MirrorProbe
- (instancetype)init { if ((self=[super init])) {
    self.virtualMirrorEnabled=YES; self.displayManagementEnabled=YES;
    self.selectedDisplayCount=1; self.selectedProfile=2; self.selectedRefreshRate=165;
    self.customLogicalWidth=2000; self.customLogicalHeight=1200;
    self.physicalIDs=@[@1]; self.routes=[NSMutableDictionary dictionary]; self.keep=YES;
    self.physicalRate=165;
} return self; }
- (NSArray *)physicalDisplayIDs { return self.physicalIDs; }
- (NSArray *)IDsForVirtualDisplays:(NSArray *)displays { return displays ?: @[]; }
- (NSDictionary *)mirrorSnapshotForDisplays:(NSArray *)ids {
    NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];
    for (NSNumber *key in ids) snapshot[key]=@{@"uuid":key.stringValue,@"mirror":self.routes[key] ?: @0,@"rate":@(self.physicalRate)};
    return snapshot;
}
- (NSDictionary *)currentModesForDisplays:(NSArray *)ids { return ids.count ? @{@100:@{@"width":@(self.activeWidth),@"rate":@(self.activeRate)}} : @{}; }
- (NSMutableArray *)createVirtualDisplays:(NSUInteger)desired {
    self.creations++; if (self.failCreation) return nil;
    self.catalogWidth=self.activeWidth=[self currentProfile].logicalWidth; self.activeRate=self.selectedRefreshRate;
    NSMutableArray *ids=[NSMutableArray array]; for(NSUInteger i=0;i<desired;i++) [ids addObject:@(100+i)]; return ids;
}
- (BOOL)advertiseVirtualDisplays:(NSArray *)displays profile:(DisplayProfile)p rate:(double)rate {
    self.advertisements++;
    if (displays.count) { self.catalogWidth=self.activeWidth=p.logicalWidth; self.activeRate=rate; } return YES;
}
- (NSDictionary *)virtualModePlan:(NSArray *)ids profile:(DisplayProfile)p rate:(double)rate { (void)rate; return ids.count && p.logicalWidth==self.catalogWidth ? @{@100:@"virtual-mode"} : nil; }
- (BOOL)configureModes:(NSDictionary *)modes { (void)modes; self.commits++; return YES; }
- (NSDictionary *)physicalMirrorModePlan:(NSArray *)ids rate:(double)rate error:(NSString **)error {
    (void)rate; if (self.unsupportedRate) { if (error) *error=@"Unsupported physical refresh rate"; return nil; }
    NSMutableDictionary *plan=[NSMutableDictionary dictionary]; for (NSNumber *key in ids) plan[key]=@"physical-mode"; return plan;
}
- (BOOL)physicalMirrorDisplays:(NSArray *)ids matchRate:(double)rate {
    return !ids.count || fabs(self.physicalRate-rate)<0.6;
}
- (BOOL)configureMirrorPlan:(NSDictionary *)virtualPlan physicalPlan:(NSDictionary *)physicalPlan routes:(NSDictionary *)routes sources:(NSArray *)sources {
    (void)virtualPlan; (void)physicalPlan; (void)sources; self.commits++;
    if (self.failMirror) return NO;
    self.activeWidth=[self currentProfile].logicalWidth; self.activeRate=self.selectedRefreshRate;
    if (!self.failPhysicalRate) self.physicalRate=self.selectedRefreshRate;
    [self.routes addEntriesFromDictionary:routes]; return YES;
}
- (BOOL)mirrorRoutesAreCurrent:(NSDictionary *)routes {
    for (NSNumber *key in routes) if (![routes[key] isEqual:self.routes[key]]) return NO; return YES;
}
- (BOOL)virtualSources:(NSArray *)ids matchProfile:(DisplayProfile)p rate:(double)rate {
    return ids.count && !self.failVerify && self.activeWidth==p.logicalWidth && self.activeRate==rate;
}
- (BOOL)restoreMirrorSnapshot:(NSDictionary *)snapshot {
    self.restores++; if (self.failRestore) return NO;
    for (NSNumber *key in snapshot) { self.routes[key]=snapshot[key][@"mirror"]; self.physicalRate=[snapshot[key][@"rate"] doubleValue]; } return YES;
}
- (BOOL)restoreModes:(NSDictionary *)previous {
    if (previous[@100]) { self.activeWidth=[previous[@100][@"width"] unsignedIntValue]; self.activeRate=[previous[@100][@"rate"] doubleValue]; }
    return YES;
}
- (BOOL)confirmUnifiedDisplaySettings { return self.keep; }
- (BOOL)topologyMatchesPhysical:(NSArray *)physical virtualIDs:(NSArray *)sources { (void)physical; (void)sources; return !self.topologyChanged; }
- (void)persistUnifiedSettings { self.saves++; }
- (void)rebuildMenu {}
- (void)showError:(NSString *)error { self.lastError=error; }
- (void)scheduleDisplayReconciliation { self.reconciliations++; }
@end
static void apply(MirrorProbe *p) { [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:165]; }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    MirrorProbe *p=[MirrorProbe new]; apply(p);
    assert(p.lastSettingsApplyKept && p.saves==1 && p.displays.count==1 && [p.routes[@1] isEqual:@100]);
    assert(p.mirrorOriginals.count==1 && p.mirrorConfigurationConfirmed);
    [p startDisplay:nil]; assert(p.creations==1 && p.commits==1); // No callback rebuild loop.
    [p applyUnifiedSettingsProfile:3 width:2000 height:1200 rate:165];
    assert(p.creations==1 && p.activeWidth==2048 && [p.displays.firstObject isEqual:@100]); // Stable source ID.
    [p stopDisplay:@1]; assert(!p.displays.count && !p.mirrorOriginals.count && [p.routes[@1] isEqual:@0]);
    p=[MirrorProbe new]; p.physicalIDs=@[@1,@2]; apply(p);
    assert(p.displays.count==1 && [p.routes[@1] isEqual:@100] && [p.routes[@2] isEqual:@100]);
    p.physicalIDs=@[]; [p startDisplay:nil]; assert(p.creations==1 && p.displays.count==1);
    p.physicalIDs=@[@3]; [p startDisplay:nil]; assert(p.creations==1 && [p.routes[@3] isEqual:@100]);
    p=[MirrorProbe new]; p.physicalIDs=@[]; apply(p); assert(p.saves==1 && p.displays.count==1);
    p=[MirrorProbe new]; p.keep=NO; apply(p);
    assert(!p.lastSettingsApplyKept && p.saves==0 && p.restores==1 && !p.displays.count && p.suspendSavedSettings);
    [p startDisplay:nil]; assert(p.creations==1); // Cancel/timeout cannot retry behind the user's back.
    p=[MirrorProbe new]; p.failMirror=YES; apply(p); assert(p.saves==0 && !p.displays.count && p.restores==1);
    p=[MirrorProbe new]; p.failCreation=YES; apply(p); assert(p.saves==0 && !p.displays.count);
    p=[MirrorProbe new]; p.failVerify=YES; apply(p); assert(p.saves==0 && p.restores==1);
    p=[MirrorProbe new]; p.topologyChanged=YES; apply(p); assert(p.saves==0 && !p.displays.count);
    p=[MirrorProbe new]; p.keep=NO; p.failRestore=YES; apply(p);
    assert(p.displays.count==1 && p.mirrorOriginals.count==1 && p.saves==0); // Never discard the only surviving source.
    [p stopDisplay:@1]; assert(p.displays.count==1); // Failed restore blocks source removal.
    p=[MirrorProbe new]; p.physicalIDs=nil; apply(p); assert(p.creations==0 && p.saves==0);
    p=[MirrorProbe new]; apply(p);
    [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:60];
    assert(p.lastSettingsApplyKept && p.physicalRate==60 && p.activeRate==60 && p.creations==1 && p.commits==2);
    assert(p.advertisements==0); // Rate changes select existing modes, never republish the catalog.
    [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:165];
    assert(p.lastSettingsApplyKept && p.physicalRate==165 && p.activeRate==165 && p.creations==1 && p.advertisements==0);
    for (NSUInteger i=0;i<100;i++) [p startDisplay:nil];
    assert(p.creations==1 && p.commits==3); // Healthy callbacks must not reallocate or commit modes.
    p.physicalRate=60;
    [p startDisplay:nil];
    assert(p.commits==3 && p.suspendSavedSettings && p.displaySettingsIssue.length);
    for (NSUInteger i=0;i<100;i++) [p startDisplay:nil];
    assert(p.commits==3 && p.physicalRate==60); // Do not fight an external settings change.
    [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:60];
    assert(p.lastSettingsApplyKept && !p.suspendSavedSettings && p.activeRate==60);
    p=[MirrorProbe new]; p.unsupportedRate=YES; apply(p);
    assert(p.creations==0 && p.commits==0 && p.saves==0 && p.lastError && p.suspendSavedSettings);
    p=[MirrorProbe new]; apply(p); p.failPhysicalRate=YES;
    [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:60];
    assert(!p.lastSettingsApplyKept && p.saves==1 && p.physicalRate==165 && p.activeRate==165 && p.restores==1 && p.suspendSavedSettings);
    p=[MirrorProbe new]; apply(p); p.keep=NO;
    [p applyUnifiedSettingsProfile:2 width:2000 height:1200 rate:60];
    assert(!p.lastSettingsApplyKept && p.saves==1 && p.physicalRate==165 && p.activeRate==165);
    puts("PASS: synchronized physical/virtual refresh, unsupported-rate preflight, physical mismatch and cancel rollback, stable source IDs, 100 callback no-op checks and failure-safe source retention.");
} }
