#define RD_DISPLAY_STATE_HELPER_TEST 1
#import "../DisplayStateHelper.m"
#include <assert.h>

static NSArray *Parse(id value,NSMutableArray *errors) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:NULL];
    return RDDSParseTargets(data,errors);
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    BOOL liveRead=argc==2&&!strcmp(argv[1],"--live-readonly");
    if(argc>2||(argc==2&&!liveRead))return 64;
    assert(RDDSModeMatchesBounds(2048,1152,CGRectMake(0,0,2048,1152),0));
    assert(!RDDSModeMatchesBounds(800,600,CGRectMake(0,0,2048,1152),0));
    assert(!RDDSModeMatchesBounds(2048,1152,CGRectMake(0,0,800,600),0));
    assert(RDDSModeMatchesBounds(2048,1152,CGRectMake(-1152,0,1152,2048),90));
    assert(RDDSModeMatchesBounds(1152,2048,CGRectMake(-1152,0,1152,2048),90));
    assert(RDDSModeMatchesBounds(2048,1152,CGRectMake(0,-2048,1152,2048),270));
    assert(RDDSModeMatchesBounds(2048,1152,CGRectMake(0,0,2048,1152),180));
    assert(!RDDSModeMatchesBounds(2048,1152,CGRectMake(0,0,2048,1152),45));
    assert(!RDDSModeMatchesBounds(2048,1152,CGRectNull,0));
    assert(!RDDSModeMatchesBounds(2048,1152,CGRectMake(0,0,NAN,1152),0));
    // Pure fallback validation. Cocoa and CG global origins intentionally differ.
    CGRect desktop=CGRectMake(-2048,0,2048,1152);
    RDDSScreenSample screen={2,CGRectMake(-2048,100,2048,1152),2,CGRectMake(0,0,4096,2304)};
    CVTime nominal={.timeValue=145456,.timeScale=24000000,.flags=0};
    assert(!RDDSModeMatchesBounds(800,600,desktop,0));
    NSDictionary *fallback=RDDSFallbackMode(2,desktop,0,screen,2,2,nominal,nominal,NO);
    assert(fallback&&[fallback[@"width"] unsignedIntValue]==2048&&[fallback[@"pixelWidth"] unsignedIntValue]==4096);
    assert(fabs([fallback[@"hz"] doubleValue]-164.99835001649984)<0.000001&&[fallback[@"refreshSource"] isEqual:@"CVDisplayLinkNominal"]);
    assert(RDDSFallbackMode(2,desktop,180,screen,2,2,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,desktop,90,screen,2,2,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,desktop,270,screen,2,2,nominal,nominal,NO));
    RDDSScreenSample badScreen=screen;badScreen.display=3;
    assert(!RDDSFallbackMode(2,desktop,0,badScreen,2,2,nominal,nominal,NO));
    badScreen=screen;badScreen.frame.size.width=800;
    assert(!RDDSFallbackMode(2,desktop,0,badScreen,2,2,nominal,nominal,NO));
    for(NSNumber *scale in @[@0.5,@1.5,@4.1,@(NAN),@(INFINITY)]) {
        badScreen=screen;badScreen.scale=scale.doubleValue;
        assert(!RDDSFallbackMode(2,desktop,0,badScreen,2,2,nominal,nominal,NO));
    }
    badScreen=screen;badScreen.backing.size.width=4095;
    assert(!RDDSFallbackMode(2,desktop,0,badScreen,2,2,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,CGRectMake(0,0,1024,1152),0,screen,2,2,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,desktop,0,screen,3,2,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,3,nominal,nominal,NO));
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,nominal,nominal,YES));
    CVTime invalidPeriod=nominal;invalidPeriod.flags=kCVTimeIsIndefinite;
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,invalidPeriod,invalidPeriod,NO));
    invalidPeriod=nominal;invalidPeriod.timeValue=0;
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,invalidPeriod,invalidPeriod,NO));
    invalidPeriod=nominal;invalidPeriod.timeScale=0;double noDefault=165;
    assert(!RDDSNominalPairValid(2,2,2,invalidPeriod,invalidPeriod,NO,&noDefault)&&noDefault==0);
    invalidPeriod=nominal;invalidPeriod.timeValue++;
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,nominal,invalidPeriod,NO));
    invalidPeriod=(CVTime){.timeValue=1,.timeScale=1001,.flags=0};
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,invalidPeriod,invalidPeriod,NO));
    invalidPeriod=(CVTime){.timeValue=2,.timeScale=1,.flags=0};
    assert(!RDDSFallbackMode(2,desktop,0,screen,2,2,invalidPeriod,invalidPeriod,NO));
    assert(RDDSScreenSamplesEqual(screen,screen));badScreen=screen;badScreen.frame.origin.y++;
    assert(!RDDSScreenSamplesEqual(screen,badScreen));badScreen=screen;badScreen.scale=1;
    assert(!RDDSScreenSamplesEqual(screen,badScreen));badScreen=screen;badScreen.backing.size.height++;
    assert(!RDDSScreenSamplesEqual(screen,badScreen));
    NSString *uuid=@"55E27CA8-9666-4C7E-BF7C-623AC29A32CD";
    NSMutableArray *errors=[NSMutableArray array];
    NSArray *parsed=Parse(@[@{@"displayID":@2,@"uuid":uuid.lowercaseString}],errors);
    assert(parsed.count==1&&!errors.count&&[parsed[0][@"uuid"] isEqual:uuid]);
    NSArray *invalid=@[@[],@{},@[@1],@[@{@"displayID":@YES,@"uuid":uuid}],@[@{@"displayID":@0,@"uuid":uuid}],@[@{@"displayID":@(-1),@"uuid":uuid}],@[@{@"displayID":@1.5,@"uuid":uuid}],@[@{@"displayID":@4294967296ULL,@"uuid":uuid}],@[@{@"displayID":@2,@"uuid":@"bad"}],@[@{@"displayID":@2,@"uuid":uuid},@{@"displayID":@2,@"uuid":uuid}]];
    for(id value in invalid){errors=[NSMutableArray array];assert(!Parse(value,errors)&&errors.count);}
    errors=[NSMutableArray array];assert(!RDDSParseTargets([@"not json" dataUsingEncoding:NSUTF8StringEncoding],errors)&&errors.count);
    NSMutableArray *tooMany=[NSMutableArray array];for(NSUInteger i=1;i<=65;i++)[tooMany addObject:@{@"displayID":@(i),@"uuid":uuid}];
    errors=[NSMutableArray array];assert(!Parse(tooMany,errors)&&errors.count);
    NSDictionary *live=nil;
    if(liveRead) {
    // Fresh read only: a nonexistent display must never turn into mode 0.
    NSDictionary *offline=RDDSReadTargets(@[@{@"displayID":@(UINT32_MAX),@"uuid":uuid}]);
    assert(![offline[@"observations"] count]&&[offline[@"errors"] count]==1&&[offline[@"errors"][0][@"code"] isEqual:@"Offline"]);
    // Read a presently online unmirrored target, physical or virtual; do not
    // hard-code an ID or create a display in this test.
    CGDirectDisplayID ids[64];uint32_t count=0;assert(CGGetOnlineDisplayList(64,ids,&count)==kCGErrorSuccess);
    for(uint32_t i=0;i<count&&i<64;i++) {
        if(CGDisplayMirrorsDisplay(ids[i])||CGDisplayIsInMirrorSet(ids[i]))continue;
        NSString *currentUUID=RDDSUUID(ids[i]);if(!currentUUID)continue;
        live=RDDSReadTargets(@[@{@"displayID":@(ids[i]),@"uuid":currentUUID}]);
        assert(![live[@"errors"] count]&&[live[@"observations"] count]==1);
        assert([live[@"observations"][0][@"width"] unsignedLongLongValue]>0&&[live[@"observations"][0][@"pixelWidth"] unsignedLongLongValue]>0);
        NSString *wrongUUID=[currentUUID isEqual:uuid]?@"00000000-0000-0000-0000-000000000001":uuid;
        NSDictionary *wrong=RDDSReadTargets(@[@{@"displayID":@(ids[i]),@"uuid":wrongUUID}]);
        assert(![wrong[@"observations"] count]&&[wrong[@"errors"] count]==1&&[wrong[@"errors"][0][@"code"] isEqual:@"UUIDMismatch"]);
        break;
    }
    }
    puts(liveRead?"PASS: guarded Cocoa/CoreVideo fallback and existing read-only identity/protocol checks.":"PASS: pure Cocoa/CV validation, mode/bounds conflict, invalid sources, stability and existing target protocol; no display API calls.");
    return RDDSEmit(live?:@{@"schemaVersion":@1,@"observations":@[],@"errors":@[]},0);
} }
