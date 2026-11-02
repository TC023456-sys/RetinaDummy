// This executable only enumerates current/native modes; never configures them.
#define main RetinaAppMain
#import "../main.m"
#undef main
int main(void) { @autoreleasepool {
    AppDelegate *delegate = [AppDelegate new];
    NSArray *onlinePhysical = [delegate physicalDisplayIDs];
    assert(onlinePhysical);
    NSString *mirrorError=nil;
    NSDictionary *outputs=[delegate physicalMirrorModePlan:onlinePhysical rate:60 error:&mirrorError];
    if (outputs) {
        for (NSNumber *key in outputs) {
            CGDisplayModeRef mode=(__bridge CGDisplayModeRef)outputs[key];
            assert(fabs(CGDisplayModeGetRefreshRate(mode)-60)<0.6);
            assert(CGDisplayModeGetWidth(mode)==CGDisplayModeGetPixelWidth(mode));
            printf("READ-ONLY: physical %u candidate %zux%zu @ %.2f Hz\n",key.unsignedIntValue,CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetRefreshRate(mode));
        }
    } else { assert(mirrorError); puts("READ-ONLY: 60 Hz unavailable; no modes applied."); }
    NSMutableArray *ids=[NSMutableArray array];
    for (NSNumber *key in onlinePhysical) {
        if (!CGDisplayIsInMirrorSet(key.unsignedIntValue)) [ids addObject:key];
        else puts("SKIP: mirrored physical target uses the virtual-source mode, not native-mode preflight.");
    }
    NSArray *formats = [delegate nativeFormatsForDisplays:ids];
    NSUInteger checked=0,hiddenCandidates=0;
    for (NSDictionary *format in formats) {
        delegate.physicalPixelWidth=[format[@"pixelWidth"] unsignedIntValue];
        delegate.physicalPixelHeight=[format[@"pixelHeight"] unsignedIntValue];
        for (NSNumber *rate in format[@"rates"]) {
            NSString *error=nil;
            NSDictionary *plan=[delegate modePlanForDisplays:ids width:[format[@"width"] unsignedIntValue] height:[format[@"height"] unsignedIntValue] rate:rate.doubleValue error:&error];
            if (!plan) {
                // Hidden candidates are advertised separately from public CG
                // modes. Confirm exact CGS presence without applying a plan.
                assert(ids.count==1);
                RDNativeModeRequest request={ [format[@"width"] unsignedIntegerValue], [format[@"height"] unsignedIntegerValue], [format[@"pixelWidth"] unsignedIntegerValue], [format[@"pixelHeight"] unsignedIntegerValue], rate.doubleValue };
                assert(RDNMFindMode([ids[0] unsignedIntValue],request));
                ++hiddenCandidates;
            } else assert(!error);
            ++checked;
        }
    }
    printf("PASS: %lu format/rate candidates enumerated, including %lu hidden CGS candidates; no modes applied or stability claimed.\n",(unsigned long)checked,(unsigned long)hiddenCandidates);
    delegate.physicalPixelWidth=0; delegate.physicalPixelHeight=0;
    for (NSNumber *key in ids) {
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(key.unsignedIntValue);
        assert(mode);
        size_t width=CGDisplayModeGetWidth(mode), height=CGDisplayModeGetHeight(mode);
        double rate=CGDisplayModeGetRefreshRate(mode);
        if (CGDisplayModeGetPixelWidth(mode)==width*2 && CGDisplayModeGetPixelHeight(mode)==height*2 && rate>0) {
            NSString *error=nil;
            NSDictionary *plan=[delegate modePlanForDisplays:@[key] width:(unsigned int)width height:(unsigned int)height rate:rate error:&error];
            assert(plan && !error && [delegate modesAreCurrent:plan]);
            printf("PASS: native current 2x HiDPI mode %zux%zu @ %.2f Hz found and verified (read-only).\n",width,height,rate);
        }
        CGDisplayModeRelease(mode);
    }
    puts("PASS: live mode enumeration completed without a display transaction.");
} }
