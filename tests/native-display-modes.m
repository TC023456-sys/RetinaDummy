#import "../NativeDisplayModes.h"
#include <assert.h>
#include <stdio.h>

static NSString *const UUID=@"55E27CA8-9666-4C7E-BF7C-623AC29A32CD";
static NSDictionary *State(RDNativeModeRequest mode) { return @{@2:RDNMRequestInfo(mode)}; }
static NSDictionary *Counted(NSDictionary *state,NSNumber *count) {
    NSMutableDictionary *mode=[state[@2] mutableCopy];mode[@"onlineDisplayCount"]=count;return @{@2:mode};
}
static NSDictionary *Plan(RDNativeModeRequest before,RDNativeModeRequest target) {
    return @{@"entries":@[@{@"displayID":@2,@"identity":@{@"uuid":UUID},@"before":RDNMRequestInfo(before)}],@"request":RDNMRequestInfo(target)};
}
static BOOL Exercise(NSDictionary *plan,NSArray *states,BOOL accepted,BOOL committed,NSUInteger *applies,NSUInteger *rollbacks,NSString **error) {
    __block NSUInteger readIndex=0,applyCount=0,rollbackCount=0;
    BOOL result=RDNMApplyPlanWithReaders(plan,^NSDictionary *(NSArray *entries,NSString **readError) {
        (void)entries;assert(readIndex<states.count);id value=states[readIndex++];
        if(value==NSNull.null){if(readError)*readError=@"observer unavailable or identity changed";return nil;}return value;
    },^BOOL(NSArray *entries,RDNativeModeRequest target,BOOL restoring,NSDictionary *fresh,BOOL *didCommit) {
        (void)entries;(void)target;assert(fresh);
        if(restoring){rollbackCount++;assert(fresh==states[1]);}else applyCount++;
        *didCommit=committed;return accepted;
    },error);
    *applies=applyCount;*rollbacks=rollbackCount;return result;
}
static BOOL BridgeExercise(NSDictionary *plan,NSArray *states,NSArray *accepted,NSArray *committed,NSMutableArray *calls,RDNMRecoveryFailure *failure,NSString **error) {
    __block NSUInteger readIndex=0,callIndex=0;
    NSDictionary *initial=plan[@"entries"][0][@"before"];
    BOOL result=RDNMApplyPlanWithReadersWithFailure(plan,^NSDictionary *(NSArray *entries,NSString **readError) {
        (void)entries;assert(readIndex<states.count);id value=states[readIndex++];
        if(value==NSNull.null){if(readError)*readError=@"fresh unavailable or identity changed";return nil;}return value;
    },^BOOL(NSArray *entries,RDNativeModeRequest request,BOOL restoring,NSDictionary *fresh,BOOL *didCommit) {
        assert(fresh&&callIndex<accepted.count&&callIndex<committed.count);
        assert([entries[0][@"before"] isEqual:initial]); // Never replace original800 with bridge1x.
        [calls addObject:@{@"restoring":@(restoring),@"request":RDNMRequestInfo(request),@"before":entries[0][@"before"]}];
        *didCommit=[committed[callIndex] boolValue];return [accepted[callIndex++] boolValue];
    },failure,error);
    assert(readIndex==states.count);return result;
}
static BOOL CancelExercise(NSDictionary *plan,NSArray *states,NSDictionary *reverse,BOOL accepted,NSMutableArray *events,NSString **error) {
    __block NSUInteger readIndex=0;
    BOOL result=RDNMRestoreNativePlanOriginalWithReaders(plan,^NSDictionary *(NSArray *entries,NSString **readError){
        (void)entries;assert(readIndex<states.count);id value=states[readIndex++];if(value==NSNull.null){if(readError)*readError=@"fresh unavailable/identity changed";return nil;}return value;
    },^NSDictionary *(NSNumber *display,RDNativeModeRequest original,NSString **planError){
        (void)planError;[events addObject:@{@"event":@"build",@"displayID":display,@"original":RDNMRequestInfo(original)}];return reverse;
    },^BOOL(NSDictionary *value,NSString **applyError){
        [events addObject:@{@"event":@"apply",@"reverse":value}];if(!accepted&&applyError)*applyError=@"reverse attempt kept selected target";return accepted;
    },error);
    assert(readIndex==states.count);return result;
}

int main(void) { @autoreleasepool {
    assert(sizeof(RDNativeModeDescription)==212);
    assert(offsetof(RDNativeModeDescription,freq)==190);
    assert(offsetof(RDNativeModeDescription,density)==208);
    RDNativeModeRequest r={2048,1152,4096,2304,165};
    RDNativeModeDescription d={.modeNumber=124,.flags=0x00200001,.width=2048,.height=1152,.freq=165,.density=2};
    assert(RDNativeRequestValid(r)&&RDNativeDescriptionMatches(&d,r));
    d.flags|=0x40000000;assert(!RDNativeDescriptionMatches(&d,r));d.flags&=~0x40000000u;
    d.density=1;assert(!RDNativeDescriptionMatches(&d,r));
    d.density=NAN;assert(!RDNativeDescriptionMatches(&d,r));
    d.density=INFINITY;assert(!RDNativeDescriptionMatches(&d,r));
    d.density=0;assert(!RDNativeDescriptionMatches(&d,r));
    d.density=5;assert(!RDNativeDescriptionMatches(&d,r));d.density=2;
    d.freq=60;assert(!RDNativeDescriptionMatches(&d,r));d.freq=165;
    d.width=1920;assert(!RDNativeDescriptionMatches(&d,r));d.width=2048;
    d.height=1080;assert(!RDNativeDescriptionMatches(&d,r));d.height=1152;
    assert(!RDNativeDescriptionMatches(NULL,r));
    RDNativeModeRequest bad=r;bad.width=0;assert(!RDNativeRequestValid(bad));
    bad=r;bad.pixelWidth=2048;assert(!RDNativeRequestValid(bad));
    bad=r;bad.pixelWidth=32769;assert(!RDNativeRequestValid(bad));
    bad=r;bad.rate=NAN;assert(!RDNativeRequestValid(bad));
    bad=r;bad.rate=0;assert(!RDNativeRequestValid(bad));
    assert(RDNativeRateMatches(164.99835,165)&&!RDNativeRateMatches(144,165)&&!RDNativeRateMatches(60,165));
    assert(!RDNativeRateMatches(NAN,165)&&!RDNativeRateMatches(165,INFINITY));
    RDNativeModeRequest roundtrip=RDNMRequestFromInfo(RDNMRequestInfo(r));
    assert(roundtrip.width==2048&&roundtrip.pixelWidth==4096&&roundtrip.rate==165);
    RDNativeModeRequest original={2560,1440,2560,1440,165};d.width=2560;d.height=1440;d.density=1;
    assert(RDNativeRequestValid(original)&&RDNativeDescriptionMatches(&d,original)); // Original LoDPI may be restored, never substituted for requested HiDPI.
    RDNativeModeRequest fractional={2560,1440,2560,1440,119.88};
    assert(RDNativeRequestsMatch(fractional,fractional));
    RDNativeModeRequest rounded=fractional;rounded.rate=120;
    assert(!RDNativeRequestsMatch(rounded,fractional));
    // The observer protocol converts hz into the plan's rate, and never
    // accepts a mode when any UUID/online/mirror/error check is incomplete.
    NSDictionary *plan=Plan((RDNativeModeRequest){800,600,1600,1200,165},r);
    NSDictionary *row=@{@"displayID":@2,@"uuid":UUID,@"online":@YES,@"mirrored":@NO,@"width":@2048,@"height":@1152,@"pixelWidth":@4096,@"pixelHeight":@2304,@"hz":@165};
    NSDictionary *message=@{@"schemaVersion":@1,@"observations":@[row],@"errors":@[]};
    NSData *json=[NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];NSString *error=nil;
    NSDictionary *parsed=RDNMParseFreshState(json,plan[@"entries"],&error);
    assert(parsed&&[parsed[@2][@"rate"] doubleValue]==165);
    assert(!parsed[@2][@"onlineDisplayCount"]); // Legacy non-bridge protocol remains valid.
    NSMutableDictionary *countRow=[row mutableCopy];countRow[@"onlineDisplayCount"]=@1;
    NSMutableDictionary *countMessage=[message mutableCopy];countMessage[@"observations"]=@[countRow];
    NSDictionary *countParsed=RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:countMessage options:0 error:NULL],plan[@"entries"],NULL);
    assert([countParsed[@2][@"onlineDisplayCount"] isEqual:@1]);
    countRow[@"onlineDisplayCount"]=@2;
    assert([RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:countMessage options:0 error:NULL],plan[@"entries"],NULL)[@2][@"onlineDisplayCount"] isEqual:@2]);
    for(NSNumber *badCount in @[@YES,@0,@1.5,@4097]) {
        countRow[@"onlineDisplayCount"]=badCount;
        assert(!RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:countMessage options:0 error:NULL],plan[@"entries"],NULL));
    }
    NSMutableDictionary *badMessage=[message mutableCopy];badMessage[@"schemaVersion"]=@YES;
    assert(!RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:badMessage options:0 error:NULL],plan[@"entries"],NULL));
    NSMutableDictionary *badRow=[row mutableCopy];badRow[@"uuid"]=@"00000000-0000-0000-0000-000000000001";
    badMessage=[message mutableCopy];badMessage[@"observations"]=@[badRow];
    assert(!RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:badMessage options:0 error:NULL],plan[@"entries"],NULL));
    badMessage=[message mutableCopy];badMessage[@"errors"]=@[@{@"code":@"Offline"}];
    assert(!RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:badMessage options:0 error:NULL],plan[@"entries"],NULL));
    badRow=[row mutableCopy];badRow[@"mirrored"]=@YES;badMessage=[message mutableCopy];badMessage[@"observations"]=@[badRow];
    assert(!RDNMParseFreshState([NSJSONSerialization dataWithJSONObject:badMessage options:0 error:NULL],plan[@"entries"],NULL));
    assert(!RDNMParseFreshState([@"not JSON" dataUsingEncoding:NSUTF8StringEncoding],plan[@"entries"],NULL));
    NSDictionary *before=State((RDNativeModeRequest){800,600,1600,1200,165});
    NSDictionary *target=State(r),*wrong=State((RDNativeModeRequest){1920,1080,3840,2160,165});
    NSUInteger applies=0,rollbacks=0;
    assert(Exercise(plan,@[before,target],YES,YES,&applies,&rollbacks,&error)&&applies==1&&rollbacks==0);
    assert(Exercise(plan,@[before,target],NO,YES,&applies,&rollbacks,&error)&&rollbacks==0);
    assert(!Exercise(plan,@[before,NSNull.null],YES,YES,&applies,&rollbacks,&error)&&rollbacks==0&&[error containsString:@"未自动回滚"]);
    assert(!Exercise(plan,@[before,wrong],YES,YES,&applies,&rollbacks,&error)&&rollbacks==0&&[error containsString:@"第三种设置"]);
    assert(!Exercise(plan,@[before,wrong],NO,YES,&applies,&rollbacks,&error)&&rollbacks==0);
    assert(!Exercise(plan,@[before,before],YES,YES,&applies,&rollbacks,&error)&&rollbacks==0&&[error containsString:@"未追加回滚写入"]);
    assert(!Exercise(plan,@[wrong],YES,YES,&applies,&rollbacks,&error)&&applies==0&&rollbacks==0);
    assert(!Exercise(plan,@[NSNull.null],YES,YES,&applies,&rollbacks,&error)&&applies==0);
    assert(Exercise(Plan(r,r),@[target],YES,YES,&applies,&rollbacks,&error)&&applies==0&&rollbacks==0);
    NSDictionary *singleBefore=Counted(before,@1),*singleTarget=Counted(target,@1),*singleWrong=Counted(wrong,@1);
    NSDictionary *bridgeState=Counted(State((RDNativeModeRequest){2048,1152,2048,1152,165}),@1);
    NSMutableDictionary *bridgePlan=[plan mutableCopy];NSMutableDictionary *hiddenEntry=[plan[@"entries"][0] mutableCopy];
    hiddenEntry[@"modeNumber"]=@124;hiddenEntry[@"before"]=singleBefore[@2];bridgePlan[@"entries"]=@[hiddenEntry];
    NSDictionary *bridgeRequest=RDNMBridgeRequest(bridgePlan);
    assert([bridgeRequest[@"width"] unsignedIntValue]==2048&&[bridgeRequest[@"pixelWidth"] unsignedIntValue]==2048&&[bridgeRequest[@"rate"] doubleValue]==165);
    bridgePlan[@"bridgeRequest"]=bridgeRequest;
    RDNMRecoveryFailure failure=RDNMRecoveryFailureStop;NSMutableArray *calls=[NSMutableArray array];
    assert(BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,singleTarget],@[@YES,@YES],@[@YES,@YES],calls,&failure,&error));
    assert(calls.count==2&&failure==RDNMRecoveryFailureNone&&[calls[0][@"request"] isEqual:bridgeRequest]&&[calls[1][@"request"] isEqual:RDNMRequestInfo(r)]);
    calls=[NSMutableArray array];
    assert(BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,singleTarget],@[@NO,@NO],@[@YES,@YES],calls,&failure,&error));
    // Only the already-confirmed bridge is a state this engine may roll back.
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,bridgeState,singleBefore],@[@YES,@YES,@YES],@[@YES,@YES,@YES],calls,&failure,&error));
    assert(calls.count==3&&[calls[2][@"restoring"] boolValue]&&failure==RDNMRecoveryFailureTargetRejectedRestored&&[calls[2][@"before"] isEqual:singleBefore[@2]]);
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,bridgeState,singleBefore],@[@YES,@NO,@YES],@[@YES,@NO,@YES],calls,&failure,&error)&&calls.count==3&&failure==RDNMRecoveryFailureTargetRejectedRestored);
    // An original-state observation needs no rollback write, even after an API error.
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,singleBefore],@[@NO],@[@NO],calls,&failure,&error)&&calls.count==1&&failure==RDNMRecoveryFailureTargetRejectedRestored);
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,singleBefore],@[@YES,@YES],@[@YES,@YES],calls,&failure,&error)&&calls.count==2&&failure==RDNMRecoveryFailureTargetRejectedRestored);
    // Third modes and unavailable/changed topology must never cause a rollback.
    for(NSArray *states in @[@[singleBefore,singleWrong],@[singleBefore,NSNull.null],@[singleBefore,bridgeState,NSNull.null],@[singleBefore,bridgeState,singleWrong],@[singleBefore,bridgeState,bridgeState,NSNull.null],@[singleBefore,bridgeState,bridgeState,singleWrong]]) {
        calls=[NSMutableArray array];assert(!BridgeExercise(bridgePlan,states,@[@YES,@YES],@[@YES,@YES],calls,&failure,&error));
        assert(failure==RDNMRecoveryFailureStop);for(NSDictionary *call in calls)assert(![call[@"restoring"] boolValue]);
    }
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,bridgeState,NSNull.null],@[@YES,@YES,@YES],@[@YES,@YES,@YES],calls,&failure,&error)&&failure==RDNMRecoveryFailureStop&&[error containsString:@"无法确认结果"]);
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,bridgeState,singleWrong],@[@YES,@YES,@YES],@[@YES,@YES,@YES],calls,&failure,&error)&&calls.count==3&&failure==RDNMRecoveryFailureStop);
    // Independent online counts are mandatory at every bridge read, not only planning.
    NSDictionary *bridgeNoCount=State((RDNativeModeRequest){2048,1152,2048,1152,165});
    for(NSArray *states in @[@[before],@[Counted(before,@2)],@[singleBefore,bridgeNoCount],@[singleBefore,Counted(bridgeNoCount,@2)],@[singleBefore,bridgeState,bridgeNoCount],@[singleBefore,bridgeState,bridgeState,target],@[singleBefore,bridgeState,bridgeState,Counted(target,@2)]]) {
        calls=[NSMutableArray array];assert(!BridgeExercise(bridgePlan,states,@[@YES,@YES],@[@YES,@YES],calls,&failure,&error)&&failure==RDNMRecoveryFailureStop);
        for(NSDictionary *call in calls)assert(![call[@"restoring"] boolValue]);
    }
    calls=[NSMutableArray array];
    assert(!BridgeExercise(bridgePlan,@[singleBefore,bridgeState,bridgeState,bridgeState,before],@[@YES,@YES,@YES],@[@YES,@YES,@YES],calls,&failure,&error)&&failure==RDNMRecoveryFailureStop);
    NSMutableDictionary *ineligible=[bridgePlan mutableCopy];NSMutableDictionary *entry=[hiddenEntry mutableCopy];entry[@"publicCandidate"]=@YES;ineligible[@"entries"]=@[entry];assert(!RDNMBridgeRequest(ineligible));
    entry=[hiddenEntry mutableCopy];entry[@"before"]=bridgeState[@2];ineligible[@"entries"]=@[entry];assert(!RDNMBridgeRequest(ineligible));
    entry=[hiddenEntry mutableCopy];entry[@"before"]=before[@2];ineligible[@"entries"]=@[entry];assert(!RDNMBridgeRequest(ineligible));
    entry=[hiddenEntry mutableCopy];entry[@"before"]=Counted(before,@2)[@2];ineligible[@"entries"]=@[entry];assert(!RDNMBridgeRequest(ineligible));
    ineligible=[bridgePlan mutableCopy];ineligible[@"entries"]=@[hiddenEntry,hiddenEntry];assert(!RDNMBridgeRequest(ineligible));
    ineligible=[bridgePlan mutableCopy];ineligible[@"request"]=bridgeRequest;assert(!RDNMBridgeRequest(ineligible));
    // No bridge metadata keeps the old protocol/direct path; malformed bridge metadata stops.
    ineligible=[bridgePlan mutableCopy];[ineligible removeObjectForKey:@"bridgeRequest"];calls=[NSMutableArray array];
    assert(BridgeExercise(ineligible,@[before,target],@[@YES],@[@YES],calls,&failure,&error)&&calls.count==1&&[calls[0][@"request"] isEqual:RDNMRequestInfo(r)]);
    NSMutableDictionary *wrongRate=[bridgeRequest mutableCopy];wrongRate[@"rate"]=@60;ineligible[@"bridgeRequest"]=wrongRate;calls=[NSMutableArray array];
    assert(!BridgeExercise(ineligible,@[singleBefore],@[],@[],calls,&failure,&error)&&calls.count==0&&failure==RDNMRecoveryFailureStop);
    // Hidden menu candidates expose only guarded 2x geometry/rates, grouped and
    // deduplicated without exporting an epoch-dependent mode number.
    RDNativeModeDescription formatsInput[18]={0};
    formatsInput[0]=(RDNativeModeDescription){.modeNumber=124,.flags=0x200001,.width=2048,.height=1152,.freq=165,.density=2};
    for(NSUInteger i=1;i<18;i++)formatsInput[i]=formatsInput[0];
    formatsInput[1].modeNumber=201; // Duplicate identity must not create duplicate menu rows/rates.
    formatsInput[2].freq=120;formatsInput[3].width=1920;formatsInput[3].height=1080;formatsInput[3].freq=60;
    formatsInput[4].flags=0;formatsInput[5].flags|=0x40000000u;formatsInput[6].density=1;formatsInput[7].density=NAN;
    formatsInput[8].width=639;formatsInput[9].height=479;formatsInput[10].width=5121;formatsInput[11].height=4321;
    formatsInput[12].freq=0;formatsInput[13].freq=1001;formatsInput[14].density=3;
    formatsInput[15].width=640;formatsInput[15].height=480;formatsInput[15].freq=30;
    formatsInput[16].width=5120;formatsInput[16].height=4320;formatsInput[16].freq=1000;
    formatsInput[17].density=INFINITY;
    NSArray *formats=RDNMHiddenFormatsFromDescriptions(formatsInput,18);
    assert(formats.count==4&&[formats[0][@"width"] unsignedIntValue]==640&&[formats[3][@"width"] unsignedIntValue]==5120);
    assert(([formats[2][@"rates"] isEqual:@[@120,@165]]&&[formats[2][@"pixelWidth"] unsignedIntValue]==4096));
    for(NSDictionary *format in formats)assert(format.count==5&&!format[@"modeNumber"]);
    assert(!RDNMHiddenFormatsFromDescriptions(NULL,1).count&&!RDNMHiddenFormatsFromDescriptions(formatsInput,8193).count);
    RDNativeModeDescription roundedPublic=formatsInput[0];roundedPublic.modeNumber=42;roundedPublic.freq=120;
    // Public ID42 carries actual119.88 Hz. Its CGS integer120 representation
    // must never be appended, including when the public GUI rejects that ID.
    assert(!RDNMHiddenFormatsFromDescriptionsExcluding(&roundedPublic,1,[NSSet setWithObject:@42]).count);
    assert(RDNMHiddenFormatsFromDescriptionsExcluding(&roundedPublic,1,[NSSet setWithObject:@99]).count==1);
    // Keep confirmation is independently observed, never inferred from local cache.
    assert(RDNMPlanTargetIsCurrentWithReader(plan,^NSDictionary *(NSArray *entries,NSString **e){(void)entries;(void)e;return target;},&error));
    assert(!RDNMPlanTargetIsCurrentWithReader(plan,^NSDictionary *(NSArray *entries,NSString **e){(void)entries;(void)e;return wrong;},&error));
    assert(!RDNMPlanTargetIsCurrentWithReader(plan,^NSDictionary *(NSArray *entries,NSString **e){(void)entries;(void)e;return nil;},&error));
    // Cancel original is the immutable initial2x state, never the forward1x bridge.
    NSMutableDictionary *reverse=[Plan(r,RDNMRequestFromInfo(singleBefore[@2])) mutableCopy];
    NSMutableDictionary *reverseEntry=[reverse[@"entries"][0] mutableCopy];reverseEntry[@"before"]=singleTarget[@2];reverseEntry[@"modeNumber"]=@0;
    reverse[@"entries"]=@[reverseEntry];reverse[@"bridgeRequest"]=RDNMBridgeRequest(reverse);
    NSMutableArray *events=[NSMutableArray array];
    assert(CancelExercise(bridgePlan,@[singleBefore],reverse,YES,events,&error)&&!events.count); // Already original: zero planning/writes.
    events=[NSMutableArray array];assert(CancelExercise(bridgePlan,@[singleTarget,singleTarget,singleBefore],reverse,YES,events,&error));
    assert(events.count==2);
    assert(RDNativeRequestsMatch(RDNMRequestFromInfo(events[0][@"original"]),RDNMRequestFromInfo(singleBefore[@2])));
    assert(!RDNativeRequestsMatch(RDNMRequestFromInfo(events[0][@"original"]),RDNMRequestFromInfo(bridgeRequest)));
    for(NSArray *states in @[@[NSNull.null],@[singleWrong],@[singleTarget,NSNull.null],@[singleTarget,singleWrong]]) {
        events=[NSMutableArray array];assert(!CancelExercise(bridgePlan,states,reverse,YES,events,&error));
        for(NSDictionary *event in events)assert(![event[@"event"] isEqual:@"apply"]);
    }
    events=[NSMutableArray array];assert(CancelExercise(bridgePlan,@[singleTarget,singleBefore],reverse,YES,events,&error)&&events.count==1);
    events=[NSMutableArray array];assert(!CancelExercise(bridgePlan,@[singleTarget,singleTarget,singleTarget],reverse,NO,events,&error)&&events.count==2&&[error containsString:@"未报告原设置已恢复"]);
    events=[NSMutableArray array];assert(!CancelExercise(bridgePlan,@[singleTarget,singleTarget,NSNull.null],reverse,YES,events,&error)&&events.count==2);
    for(NSString *change in @[@"before",@"identity",@"request"]) {
        NSMutableDictionary *badReverse=[reverse mutableCopy],*badEntry=[reverseEntry mutableCopy];
        if([change isEqual:@"before"])badEntry[@"before"]=singleWrong[@2];
        if([change isEqual:@"identity"])badEntry[@"identity"]=@{@"uuid":@"00000000-0000-0000-0000-000000000001"};
        if([change isEqual:@"request"])badReverse[@"request"]=bridgeRequest;
        badReverse[@"entries"]=@[badEntry];events=[NSMutableArray array];
        assert(!CancelExercise(bridgePlan,@[singleTarget],badReverse,YES,events,&error)&&events.count==1);
    }
    // Exercise the actual reverse bridge engine: its before is selectedTarget,
    // final goal is immutable original8002x, not either intermediate1x format.
    __block NSUInteger cancelRead=0;NSArray *cancelStates=@[singleTarget,singleTarget,singleBefore];NSMutableArray *reverseCalls=[NSMutableArray array];
    NSDictionary *reverseBridge=Counted(State((RDNativeModeRequest){800,600,800,600,165}),@1);
    assert(RDNMRestoreNativePlanOriginalWithReaders(bridgePlan,^NSDictionary *(NSArray *entries,NSString **e){(void)entries;(void)e;return cancelStates[cancelRead++];},
        ^NSDictionary *(NSNumber *display,RDNativeModeRequest original,NSString **e){(void)display;(void)original;(void)e;return reverse;},
        ^BOOL(NSDictionary *value,NSString **e){RDNMRecoveryFailure outcome;return BridgeExercise(value,@[singleTarget,reverseBridge,reverseBridge,singleBefore],@[@YES,@YES],@[@YES,@YES],reverseCalls,&outcome,e);},&error));
    assert(cancelRead==3&&reverseCalls.count==2&&RDNativeRequestsMatch(RDNMRequestFromInfo(reverseCalls[1][@"request"]),RDNMRequestFromInfo(singleBefore[@2])));
    NSString *status=nil;BOOL didCommit=YES;
    assert(!RDNMTransactionWithStatus(@[],r,NO,nil,&didCommit,NO,&status)&&!didCommit&&[status containsString:@"begin=not-called"]); // No display API reached.
    RDNMModeWatch watch={0};watch.ids[0]=2;watch.count=1;atomic_init(&watch.sawSetMode,false);
    RDNMModeChanged(2,kCGDisplayBeginConfigurationFlag|kCGDisplaySetModeFlag,&watch);assert(!atomic_load(&watch.sawSetMode));
    RDNMModeChanged(99,kCGDisplaySetModeFlag,&watch);assert(!atomic_load(&watch.sawSetMode));
    RDNMModeChanged(2,kCGDisplaySetModeFlag,&watch);assert(atomic_load(&watch.sawSetMode));
    puts("PASS: guarded hidden2x grouping; fresh keep verification; immutable-original cancel/reverse bridge, unknown/drift no-write; existing safe bridge and protocol regressions; pure mocks only.");
    return 0;
} }
