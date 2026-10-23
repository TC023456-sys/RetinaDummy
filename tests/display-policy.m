#define main RetinaAppMain
#import "../main.m"
#undef main
@interface PolicyProbe : AppDelegate
@property NSUInteger physical;
@property NSUInteger creations;
@property NSUInteger reconciliations;
@end
@implementation PolicyProbe
- (NSUInteger)physicalDisplayCount { return self.physical; }
- (void)rebuildMenu {}
- (void)restorePhysicalDisplay:(id)sender { (void)sender; }
- (NSMutableArray *)createVirtualDisplays:(NSUInteger)desired {
    self.creations++;
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i=0; i<desired; i++) [a addObject:[NSObject new]];
    return a;
}
- (void)startDisplay:(id)sender { self.reconciliations++; [super startDisplay:sender]; }
@end
static void drain(void) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:0.85];
    while (end.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    PolicyProbe *d=[PolicyProbe new];
    d.selectedDisplayCount=1; d.preferPhysicalDisplays=YES; d.displayManagementEnabled=YES;
    d.physical=1; [d startDisplay:nil]; assert(d.displays.count==0 && d.creations==0);
    d.physical=0; [d scheduleDisplayReconciliation]; drain(); assert(d.displays.count==1);
    NSUInteger created=d.creations;
    [d scheduleDisplayReconciliation]; [d scheduleDisplayReconciliation]; drain();
    assert(d.displays.count==1 && d.creations==created);
    d.physical=1; [d scheduleDisplayReconciliation]; drain(); assert(d.displays.count==0);
    d.physical=0; [d scheduleDisplayReconciliation]; [d stopDisplay:[NSObject new]]; drain();
    assert(!d.displayManagementEnabled && d.displays.count==0);
    [d startDisplay:[NSObject new]]; assert(d.displays.count==1);
    d.physical=NSNotFound; [d startDisplay:nil]; assert(d.displays.count==1);
    d.physical=1; d.selectedDisplayCount=2; [d startDisplay:nil]; assert(d.displays.count==1);
    d.physical=2; [d startDisplay:nil]; assert(d.displays.count==0);
    d.physical=0; [d startDisplay:nil]; assert(d.displays.count==2);
    d.preferPhysicalDisplays=NO; d.physical=1; [d startDisplay:nil]; assert(d.displays.count==2);
    puts("PASS: physical priority, disconnect fallback, reconnect removal, idempotence, pause race, resume, enumeration failure, counts 1/2, legacy mode");
}}
