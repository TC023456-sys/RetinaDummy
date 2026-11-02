#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ColorSync/ColorSync.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <math.h>
#include <stddef.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

// Read-only CGS mode-description ABI, verified against Crisp commit
// 04baa6fe7531293aa1b386a3c5f41b5d1c4bce29. Configuration takes a CG config token.
typedef struct {
    uint32_t modeNumber, flags, width, height, depth, reserved[42];
    uint16_t reserved2, freq;
    uint32_t reserved3[4];
    float density;
} RDNativeModeDescription;
_Static_assert(sizeof(RDNativeModeDescription)==212,"CGS mode ABI size");
_Static_assert(offsetof(RDNativeModeDescription,freq)==190,"CGS frequency ABI");
_Static_assert(offsetof(RDNativeModeDescription,density)==208,"CGS density ABI");

typedef struct { NSUInteger width,height,pixelWidth,pixelHeight; double rate; } RDNativeModeRequest;
static inline BOOL RDNativeRateMatches(double actual,double requested) {
    return isfinite(actual)&&isfinite(requested)&&actual>0&&requested>0&&fabs(actual-requested)<0.1;
}
static inline BOOL RDNativeRequestValid(RDNativeModeRequest r) {
    return r.width>0&&r.height>0&&r.width<=32768&&r.height<=32768&&r.pixelWidth>0&&r.pixelHeight>0&&r.pixelWidth<=32768&&r.pixelHeight<=32768
      &&r.pixelWidth>=r.width&&r.pixelHeight>=r.height&&(uint64_t)r.pixelWidth*r.height==(uint64_t)r.pixelHeight*r.width
      &&isfinite(r.rate)&&r.rate>0&&r.rate<=1000;
}
static inline BOOL RDNativeDescriptionMatches(const RDNativeModeDescription *d,RDNativeModeRequest r) {
    return d&&RDNativeRequestValid(r)&&!(d->flags&0x40000000u)&&isfinite(d->density)&&d->density>=1.0f&&d->density<=4.0f
      &&d->width==r.width&&d->height==r.height&&RDNativeRateMatches(d->freq,r.rate)
      &&llround((double)d->width*d->density)==(long long)r.pixelWidth&&llround((double)d->height*d->density)==(long long)r.pixelHeight;
}
static inline BOOL RDNMFail(NSString **error,NSString *message) { if(error)*error=message;return NO; }
static inline NSDictionary *RDNMRequestInfo(RDNativeModeRequest r) {
    return @{@"width":@(r.width),@"height":@(r.height),@"pixelWidth":@(r.pixelWidth),@"pixelHeight":@(r.pixelHeight),@"rate":@(r.rate)};
}
static inline RDNativeModeRequest RDNMRequestFromInfo(NSDictionary *d) {
    return (RDNativeModeRequest){[d[@"width"] unsignedIntegerValue],[d[@"height"] unsignedIntegerValue],[d[@"pixelWidth"] unsignedIntegerValue],[d[@"pixelHeight"] unsignedIntegerValue],[d[@"rate"] doubleValue]};
}
typedef struct {
    CGError (*count)(CGDirectDisplayID,int *);
    CGError (*describe)(CGDirectDisplayID,int,RDNativeModeDescription *,int);
    CGError (*configure)(CGDisplayConfigRef,CGDirectDisplayID,int32_t);
    CFDictionaryRef (*displayInfo)(CGDirectDisplayID);
} RDNMFunctions;
static inline RDNMFunctions RDNMAPI(void) {
    static RDNMFunctions f;static dispatch_once_t once;
    dispatch_once(&once,^{
        void *sky=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
        void *core=dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",RTLD_LAZY);
        if(sky){f.count=dlsym(sky,"CGSGetNumberOfDisplayModes");f.describe=dlsym(sky,"CGSGetDisplayModeDescriptionOfLength");f.configure=dlsym(sky,"CGSConfigureDisplayMode");}
        if(core)f.displayInfo=dlsym(core,"CoreDisplay_DisplayCreateInfoDictionary");
    });return f;
}
static inline NSDictionary *RDNMIdentity(CGDirectDisplayID display) {
    if(!CGDisplayIsOnline(display)||CGDisplayMirrorsDisplay(display)||CGDisplayIsInMirrorSet(display))return nil;
    RDNMFunctions f=RDNMAPI();if(!f.displayInfo)return nil;
    NSDictionary *info=CFBridgingRelease(f.displayInfo(display));
    NSString *location=info[@"IODisplayLocation"];
    if([info[@"kCGDisplayIsVirtualDevice"] boolValue]||[info[@"kCGDisplayIsAirPlay"] boolValue]
      ||(!CGDisplayIsBuiltin(display)&&(![location isKindOfClass:NSString.class]||!location.length)))return nil;
    CFUUIDRef idref=CGDisplayCreateUUIDFromDisplayID(display);if(!idref)return nil;
    NSString *uuid=CFBridgingRelease(CFUUIDCreateString(NULL,idref));CFRelease(idref);
    return @{@"displayID":@(display),@"uuid":uuid,@"location":[location isKindOfClass:NSString.class]?location:@""};
}
static inline BOOL RDNMIdentityMatches(NSDictionary *entry) {
    return [RDNMIdentity([entry[@"displayID"] unsignedIntValue]) isEqual:entry[@"identity"]];
}
static inline NSDictionary *RDNMCurrent(CGDirectDisplayID display) {
    CGDisplayModeRef m=CGDisplayCopyDisplayMode(display);if(!m)return nil;
    NSDictionary *d=@{@"width":@(CGDisplayModeGetWidth(m)),@"height":@(CGDisplayModeGetHeight(m)),@"pixelWidth":@(CGDisplayModeGetPixelWidth(m)),@"pixelHeight":@(CGDisplayModeGetPixelHeight(m)),@"rate":@(CGDisplayModeGetRefreshRate(m))};CFRelease(m);return d;
}
static inline BOOL RDNativeRequestsMatch(RDNativeModeRequest a,RDNativeModeRequest b) {
    return a.width==b.width&&a.height==b.height&&a.pixelWidth==b.pixelWidth&&a.pixelHeight==b.pixelHeight&&RDNativeRateMatches(a.rate,b.rate);
}
static inline BOOL RDNMCurrentMatches(CGDirectDisplayID display,RDNativeModeRequest r) {
    NSDictionary *d=RDNMCurrent(display);RDNativeModeRequest a=RDNMRequestFromInfo(d);
    return d&&RDNativeRequestsMatch(a,r);
}
// Production uses only its signed bundle resource (or an adjacent resource for
// standalone tools). A fixed build-only override is used by recovery diagnostics.
static inline NSString *RDNMObserverPath(void) {
#ifdef RDNM_DISPLAY_STATE_HELPER_PATH
    return RDNM_DISPLAY_STATE_HELPER_PATH;
#else
    NSString *path=[NSBundle.mainBundle pathForResource:@"RetinaDisplayState" ofType:nil];
    if(!path)path=[[NSBundle.mainBundle.executablePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"RetinaDisplayState"];
    return path;
#endif
}
static inline BOOL RDNMJSONNumber(id value) {
    return [value isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID()&&isfinite([value doubleValue]);
}
static inline NSDictionary *RDNMParseFreshState(NSData *data,NSArray *entries,NSString **error) {
    if(!data.length||data.length>65536){RDNMFail(error,@"独立显示读回为空或超过限制。");return nil;}
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![value isKindOfClass:NSDictionary.class]||!RDNMJSONNumber(value[@"schemaVersion"])||![value[@"schemaVersion"] isEqual:@1]
      ||![value[@"errors"] isKindOfClass:NSArray.class]||[value[@"errors"] count]
      ||![value[@"observations"] isKindOfClass:NSArray.class]||[value[@"observations"] count]!=entries.count) {
        RDNMFail(error,@"独立显示读回未完整确认目标身份、在线与非镜像状态。");return nil;
    }
    NSMutableDictionary *expected=[NSMutableDictionary dictionary],*result=[NSMutableDictionary dictionary];
    for(NSDictionary *entry in entries)expected[entry[@"displayID"]]=entry[@"identity"][@"uuid"];
    for(id row in value[@"observations"]) {
        if(![row isKindOfClass:NSDictionary.class]){RDNMFail(error,@"独立显示读回格式无效。");return nil;}
        id number=row[@"displayID"],uuid=row[@"uuid"];
        if(!RDNMJSONNumber(number)||[number doubleValue]<1||[number doubleValue]>UINT32_MAX||floor([number doubleValue])!=[number doubleValue]
          ||![uuid isKindOfClass:NSString.class]||![uuid isEqual:expected[number]]||result[number]
          ||![row[@"online"] isEqual:@YES]||![row[@"mirrored"] isEqual:@NO]) {
            RDNMFail(error,@"独立显示读回的身份或拓扑不匹配；禁止覆盖。");return nil;
        }
        for(NSString *key in @[@"width",@"height",@"pixelWidth",@"pixelHeight"]) {
            if(!RDNMJSONNumber(row[key])||[row[key] doubleValue]<1||[row[key] doubleValue]>32768||floor([row[key] doubleValue])!=[row[key] doubleValue]) {
                RDNMFail(error,@"独立显示读回的尺寸无效。");return nil;
            }
        }
        if(!RDNMJSONNumber(row[@"hz"])||[row[@"hz"] doubleValue]<=0||[row[@"hz"] doubleValue]>1000){RDNMFail(error,@"独立显示读回的刷新率无效。");return nil;}
        NSMutableDictionary *mode=[@{@"width":row[@"width"],@"height":row[@"height"],@"pixelWidth":row[@"pixelWidth"],@"pixelHeight":row[@"pixelHeight"],@"rate":row[@"hz"]} mutableCopy];
        id onlineCount=row[@"onlineDisplayCount"];
        if(onlineCount) {
            if(!RDNMJSONNumber(onlineCount)||[onlineCount doubleValue]<entries.count||[onlineCount doubleValue]>4096||floor([onlineCount doubleValue])!=[onlineCount doubleValue]) {
                RDNMFail(error,@"独立显示读回的在线显示器计数无效。");return nil;
            }
            mode[@"onlineDisplayCount"]=onlineCount;
        }
        if(!RDNativeRequestValid(RDNMRequestFromInfo(mode))){RDNMFail(error,@"独立显示读回的模式不完整。");return nil;}
        result[number]=mode;
    }
    return result;
}
static inline NSDictionary *RDNMReadFreshState(NSArray *entries,NSString **error) {
    NSString *path=RDNMObserverPath();struct stat info;
    if(!path||lstat(path.fileSystemRepresentation,&info)||!S_ISREG(info.st_mode)||!(info.st_mode&0111)) {
        RDNMFail(error,@"独立显示读回工具不可用；无法确认当前模式。");return nil;
    }
    NSMutableArray *targets=[NSMutableArray array];
    for(NSDictionary *entry in entries)[targets addObject:@{@"displayID":entry[@"displayID"],@"uuid":entry[@"identity"][@"uuid"]}];
    NSData *request=[NSJSONSerialization dataWithJSONObject:targets options:0 error:NULL];
    if(!request||request.length>16384){RDNMFail(error,@"独立显示读回请求无效。");return nil;}
    NSTask *task=[NSTask new];NSPipe *output=[NSPipe pipe],*diagnostics=[NSPipe pipe];
    task.executableURL=[NSURL fileURLWithPath:path];task.arguments=@[@"--read-state",[[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding]];
    task.standardOutput=output;task.standardError=diagnostics;task.standardInput=[NSFileHandle fileHandleWithNullDevice];
    NSError *launchError=nil;
    if(![task launchAndReturnError:&launchError]){RDNMFail(error,@"独立显示读回工具启动失败。");return nil;}
    int descriptors[2]={output.fileHandleForReading.fileDescriptor,diagnostics.fileHandleForReading.fileDescriptor};
    for(int i=0;i<2;i++)fcntl(descriptors[i],F_SETFL,fcntl(descriptors[i],F_GETFL)|O_NONBLOCK);
    NSMutableData *buffers[2]={[NSMutableData data],[NSMutableData data]};BOOL eof[2]={NO,NO},limited=NO,timedOut=NO;
    NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+2.0;
    while(task.running||!eof[0]||!eof[1]) {
        for(int i=0;i<2;i++)if(!eof[i]) {
            unsigned char bytes[4096];ssize_t count;
            while((count=read(descriptors[i],bytes,sizeof(bytes)))>0) {
                [buffers[i] appendBytes:bytes length:(NSUInteger)count];
                if(buffers[i].length>(i?8192:65536)){limited=YES;break;}
            }
            if(count==0)eof[i]=YES;
            else if(count<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR)eof[i]=YES;
        }
        if(limited)break;
        if(NSProcessInfo.processInfo.systemUptime>=deadline){timedOut=YES;break;}
        if(!task.running&&eof[0]&&eof[1])break;
        struct pollfd waiters[2]={{descriptors[0],POLLIN|POLLHUP,0},{descriptors[1],POLLIN|POLLHUP,0}};poll(waiters,2,10);
    }
    if(limited||timedOut) {
        if(task.running)kill(task.processIdentifier,SIGKILL); // Only our own short-lived read-only child.
        [output.fileHandleForReading closeFile];[diagnostics.fileHandleForReading closeFile];
        RDNMFail(error,limited?@"独立显示读回超过输出限制，无法确认。":@"独立显示读回超时，无法确认。");return nil;
    }
    [output.fileHandleForReading closeFile];[diagnostics.fileHandleForReading closeFile];
    if(task.terminationStatus!=0){RDNMFail(error,@"独立显示读回拒绝了目标身份、在线或非镜像校验；未确认当前模式。");return nil;}
    return RDNMParseFreshState(buffers[0],entries,error);
}
static inline BOOL RDNMFreshMatches(NSDictionary *state,NSArray *entries,RDNativeModeRequest request,BOOL restoring) {
    if(!state||state.count!=entries.count)return NO;
    for(NSDictionary *entry in entries) {
        NSDictionary *mode=state[entry[@"displayID"]];
        if(!mode||!RDNativeRequestsMatch(RDNMRequestFromInfo(mode),restoring?RDNMRequestFromInfo(entry[@"before"]):request))return NO;
    }
    return YES;
}
static inline BOOL RDNMFreshSingleOnlineTarget(NSDictionary *state,NSArray *entries) {
    if(entries.count!=1||state.count!=1)return NO;
    id count=state[entries[0][@"displayID"]][@"onlineDisplayCount"];
    return RDNMJSONNumber(count)&&[count doubleValue]==1;
}
// Retained fresh public mode for restoring fractional original refresh rates.
// CGS's uint16_t frequency cannot identify e.g. 119.88 Hz precisely.
static inline CGDisplayModeRef RDNMFindPublicModeWithUsability(CGDirectDisplayID display,RDNativeModeRequest wanted,BOOL usableOnly) {
    CFArrayRef modes=CGDisplayCopyAllDisplayModes(display,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    CGDisplayModeRef result=NULL;
    for(id value in (__bridge NSArray *)modes) {
        CGDisplayModeRef mode=(__bridge CGDisplayModeRef)value;
        RDNativeModeRequest candidate={CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetPixelWidth(mode),CGDisplayModeGetPixelHeight(mode),CGDisplayModeGetRefreshRate(mode)};
        if(!(CGDisplayModeGetIOFlags(mode)&0x40000000u)&&(!usableOnly||CGDisplayModeIsUsableForDesktopGUI(mode))&&RDNativeRequestsMatch(candidate,wanted)){result=(CGDisplayModeRef)CFRetain(mode);break;}
    }
    if(modes)CFRelease(modes);return result;
}
static inline CGDisplayModeRef RDNMFindPublicMode(CGDirectDisplayID display,RDNativeModeRequest wanted) {
    return RDNMFindPublicModeWithUsability(display,wanted,NO);
}
static inline BOOL RDNMSingleOnlineTarget(CGDirectDisplayID display) {
    CGDirectDisplayID ids[2];uint32_t count=0;
    return CGGetOnlineDisplayList(2,ids,&count)==kCGErrorSuccess&&count==1&&ids[0]==display;
}
// Pure eligibility policy: only a hidden 2x target whose logical geometry must
// change can need the same-logical-size public 1x bridge.
static inline NSDictionary *RDNMBridgeRequest(NSDictionary *plan) {
    NSArray *entries=plan[@"entries"];if(entries.count!=1)return nil;
    NSDictionary *entry=entries[0];RDNativeModeRequest r=RDNMRequestFromInfo(plan[@"request"]),before=RDNMRequestFromInfo(entry[@"before"]);
    id onlineCount=entry[@"before"][@"onlineDisplayCount"];
    if(!entry[@"modeNumber"]||[entry[@"publicCandidate"] boolValue]||!RDNMJSONNumber(onlineCount)||[onlineCount doubleValue]!=1||!RDNativeRequestValid(r)
      ||r.pixelWidth!=r.width*2||r.pixelHeight!=r.height*2||(before.width==r.width&&before.height==r.height))return nil;
    return RDNMRequestInfo((RDNativeModeRequest){r.width,r.height,r.width,r.height,r.rate});
}
static inline NSNumber *RDNMFindMode(CGDirectDisplayID display,RDNativeModeRequest r) {
    RDNMFunctions f=RDNMAPI();int count=0;
    if(!f.count||!f.describe||f.count(display,&count)||count<=0||count>8192)return nil;
    for(int index=0;index<count;index++) {RDNativeModeDescription d={0};if(!f.describe(display,index,&d,sizeof(d))&&RDNativeDescriptionMatches(&d,r))return @(d.modeNumber);}
    return nil;
}

// Geometry/rate rows only: mode numbers are deliberately not exported to menus.
static inline NSArray<NSDictionary *> *RDNMHiddenFormatsFromDescriptionsExcluding(const RDNativeModeDescription *modes,NSUInteger count,NSSet<NSNumber *> *excludedModeIDs) {
    if((count&&!modes)||count>8192)return @[];
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    for(NSUInteger i=0;i<count;i++) {
        const RDNativeModeDescription *d=&modes[i];
        if([excludedModeIDs containsObject:@(d->modeNumber)])continue;
        if(!(d->flags&0x1u)||(d->flags&0x40000000u)||d->width<640||d->width>5120||d->height<480||d->height>4320
          ||!isfinite(d->density)||fabs(d->density-2.0)>0.001||d->freq<1||d->freq>1000)continue;
        RDNativeModeRequest r={d->width,d->height,d->width*2,d->height*2,d->freq};
        if(!RDNativeDescriptionMatches(d,r))continue;
        NSString *key=[NSString stringWithFormat:@"%u/%u/%u/%u",d->width,d->height,d->width*2,d->height*2];
        NSMutableDictionary *row=groups[key];
        if(!row){row=[@{@"width":@(r.width),@"height":@(r.height),@"pixelWidth":@(r.pixelWidth),@"pixelHeight":@(r.pixelHeight),@"rates":[NSMutableSet set]} mutableCopy];groups[key]=row;}
        [row[@"rates"] addObject:@(r.rate)];
    }
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *row in groups.allValues) {
        NSMutableDictionary *copy=[row mutableCopy];copy[@"rates"]=[[row[@"rates"] allObjects] sortedArrayUsingSelector:@selector(compare:)];[result addObject:copy];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        for(NSString *key in @[@"width",@"height",@"pixelWidth",@"pixelHeight"]){NSComparisonResult order=[a[key] compare:b[key]];if(order!=NSOrderedSame)return order;}return NSOrderedSame;
    }];
    return result.copy;
}
static inline NSArray<NSDictionary *> *RDNMHiddenFormatsFromDescriptions(const RDNativeModeDescription *modes,NSUInteger count) {
    return RDNMHiddenFormatsFromDescriptionsExcluding(modes,count,nil);
}
static inline NSArray<NSDictionary *> *RDNMHiddenFormatsForDisplay(CGDirectDisplayID display) {
    NSDictionary *identity=RDNMIdentity(display);if(!identity)return @[];
    CFArrayRef publicModes=CGDisplayCopyAllDisplayModes(display,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    if(!publicModes)return @[];
    NSMutableSet *excluded=[NSMutableSet set];
    // Even public modes the GUI rejects stay excluded. In particular an integer
    // CGS frequency must not re-add a public fractional mode as a different Hz.
    for(id object in (__bridge NSArray *)publicModes)[excluded addObject:@(CGDisplayModeGetIODisplayModeID((__bridge CGDisplayModeRef)object))];
    CFRelease(publicModes);
    RDNMFunctions f=RDNMAPI();int count=0;
    if(!f.count||!f.describe||f.count(display,&count)||count<1||count>8192)return @[];
    RDNativeModeDescription *modes=calloc((NSUInteger)count,sizeof(*modes));if(!modes)return @[];
    for(int i=0;i<count;i++)if(f.describe(display,i,&modes[i],sizeof(*modes)))memset(&modes[i],0,sizeof(*modes));
    NSArray *formats=RDNMHiddenFormatsFromDescriptionsExcluding(modes,(NSUInteger)count,excluded);free(modes);
    return [RDNMIdentity(display) isEqual:identity]?formats:@[];
}

// Builds a read-only plan. The original geometry comes from a new CG client,
// never from the configuring process's possibly stale CGDisplayCopyDisplayMode.
static inline NSDictionary *RDHiddenNativeModePlan(NSArray<NSNumber *> *ids,NSUInteger width,NSUInteger height,NSUInteger pixelWidth,NSUInteger pixelHeight,double rate,NSString **error) {
    RDNativeModeRequest request={width,height,pixelWidth,pixelHeight,rate};
    if(!ids.count||ids.count>64||[NSSet setWithArray:ids].count!=ids.count||!RDNativeRequestValid(request)){RDNMFail(error,@"原生显示目标或精确模式参数无效。");return nil;}
    NSMutableArray *entries=[NSMutableArray array];
    for(NSNumber *number in ids) {
        if(![number isKindOfClass:NSNumber.class]||number.unsignedLongLongValue>UINT32_MAX){RDNMFail(error,@"原生显示器标识无效。");return nil;}
        NSDictionary *identity=RDNMIdentity(number.unsignedIntValue);
        if(!identity){RDNMFail(error,@"只允许在线、未镜像且身份可确认的实体屏。");return nil;}
        [entries addObject:[@{@"displayID":number,@"identity":identity} mutableCopy]];
    }
    NSDictionary *fresh=RDNMReadFreshState(entries,error);if(!fresh)return nil;
    for(NSMutableDictionary *entry in entries) {
        CGDirectDisplayID display=[entry[@"displayID"] unsignedIntValue];NSDictionary *before=fresh[entry[@"displayID"]];entry[@"before"]=before;
        if(!RDNativeRequestsMatch(RDNMRequestFromInfo(before),request)) {
            CGDisplayModeRef publicMode=RDNMFindPublicMode(display,request);
            if(publicMode){entry[@"publicCandidate"]=@YES;CFRelease(publicMode);}
            else {NSNumber *mode=RDNMFindMode(display,request);if(!mode){RDNMFail(error,@"实体屏未提供请求的精确 HiDPI 尺寸和刷新率；未降低刷新率或改用普通模式。");return nil;}entry[@"modeNumber"]=mode;}
        }
        if(!RDNMIdentityMatches(entry)){RDNMFail(error,@"预检期间显示连接已变化；未应用。");return nil;}
    }
    NSMutableDictionary *plan=[@{@"request":RDNMRequestInfo(request),@"entries":entries} mutableCopy];
    NSDictionary *bridge=RDNMBridgeRequest(plan);
    if(bridge&&RDNMSingleOnlineTarget([entries[0][@"displayID"] unsignedIntValue])) {
        CGDisplayModeRef mode=RDNMFindPublicModeWithUsability([entries[0][@"displayID"] unsignedIntValue],RDNMRequestFromInfo(bridge),YES);
        if(mode){plan[@"bridgeRequest"]=bridge;CFRelease(mode);}
    }
    return plan;
}

typedef struct { CGDirectDisplayID ids[64];NSUInteger count;atomic_bool sawSetMode; } RDNMModeWatch;
static inline void RDNMModeChanged(CGDirectDisplayID display,CGDisplayChangeSummaryFlags flags,void *context) {
    if((flags&kCGDisplayBeginConfigurationFlag)||!(flags&kCGDisplaySetModeFlag))return;
    RDNMModeWatch *watch=context;for(NSUInteger i=0;i<watch->count;i++)if(watch->ids[i]==display){atomic_store(&watch->sawSetMode,true);return;}
}
static inline void RDNMPumpDisplayEvents(RDNMModeWatch *watch) {
    NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+0.75;
    do {
        SInt32 result=CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.025,false);
        if(atomic_load(&watch->sawSetMode))break;
        if(result==kCFRunLoopRunFinished)[NSThread sleepForTimeInterval:0.005];
    } while(NSProcessInfo.processInfo.systemUptime<deadline);
}
// Fresh enumeration for both apply and rollback. Public modes remain preferred.
// The callback is registered before the transaction and removed on every path.
static inline BOOL RDNMTransactionWithStatus(NSArray *entries,RDNativeModeRequest request,BOOL restoring,NSDictionary *freshCurrent,BOOL *committed,BOOL publicOnly,NSString **diagnostics) {
    *committed=NO;NSInteger begin=-1,configure=-1,complete=-1,registration=-1;BOOL registered=NO;
    RDNMModeWatch watch={0};atomic_init(&watch.sawSetMode,false);
    @try {
        if(!freshCurrent||!entries.count||entries.count>64)return NO;
        if(publicOnly&&(!RDNMFreshSingleOnlineTarget(freshCurrent,entries)||!RDNMSingleOnlineTarget([entries[0][@"displayID"] unsignedIntValue])))return NO;
        NSMutableArray *changes=[NSMutableArray array];RDNMFunctions f=RDNMAPI();
        for(NSDictionary *entry in entries) {
            if(!RDNMIdentityMatches(entry))return NO;CGDirectDisplayID display=[entry[@"displayID"] unsignedIntValue];
            RDNativeModeRequest wanted=restoring?RDNMRequestFromInfo(entry[@"before"]):request;
            if(RDNativeRequestsMatch(RDNMRequestFromInfo(freshCurrent[entry[@"displayID"]]),wanted))continue;
            CGDisplayModeRef publicMode=RDNMFindPublicModeWithUsability(display,wanted,publicOnly);
            if(publicMode){[changes addObject:@{@"displayID":@(display),@"publicMode":(__bridge id)publicMode}];CFRelease(publicMode);}
            else {if(publicOnly)return NO;NSNumber *mode=RDNMFindMode(display,wanted);if(!mode||!f.configure)return NO;[changes addObject:@{@"displayID":@(display),@"modeNumber":mode}];}
        }
        if(!changes.count)return YES;
        watch.count=entries.count;for(NSUInteger i=0;i<entries.count;i++)watch.ids[i]=[entries[i][@"displayID"] unsignedIntValue];
        registration=CGDisplayRegisterReconfigurationCallback(RDNMModeChanged,&watch);if(registration!=kCGErrorSuccess)return NO;registered=YES;
        CGDisplayConfigRef config=NULL;begin=CGBeginDisplayConfiguration(&config);if(begin!=kCGErrorSuccess||!config)return NO;
        for(NSDictionary *entry in entries)if(!RDNMIdentityMatches(entry)){CGCancelDisplayConfiguration(config);return NO;}
        for(NSDictionary *change in changes) {
            CGDirectDisplayID display=[change[@"displayID"] unsignedIntValue];
            configure=change[@"publicMode"]?CGConfigureDisplayWithDisplayMode(config,display,(__bridge CGDisplayModeRef)change[@"publicMode"],NULL):f.configure(config,display,[change[@"modeNumber"] intValue]);
            if(configure!=kCGErrorSuccess){CGCancelDisplayConfiguration(config);return NO;}
        }
        for(NSDictionary *entry in entries)if(!RDNMIdentityMatches(entry)){CGCancelDisplayConfiguration(config);return NO;}
        *committed=YES;complete=CGCompleteDisplayConfiguration(config,kCGConfigureForSession);RDNMPumpDisplayEvents(&watch);
        return complete==kCGErrorSuccess;
    } @finally {
        if(registered)CGDisplayRemoveReconfigurationCallback(RDNMModeChanged,&watch);
        if(diagnostics)*diagnostics=[NSString stringWithFormat:@"CG register=%@ begin=%@ configure=%@ complete=%@ setMode=%@",
            registration<0?@"not-called":@(registration),begin<0?@"not-called":@(begin),configure<0?@"not-called":@(configure),complete<0?@"not-called":@(complete),atomic_load(&watch.sawSetMode)?@"YES":@"NO"];
    }
}
static inline BOOL RDNMTransaction(NSArray *entries,RDNativeModeRequest request,BOOL restoring,NSDictionary *freshCurrent,BOOL *committed) {
    return RDNMTransactionWithStatus(entries,request,restoring,freshCurrent,committed,NO,NULL);
}

typedef NSDictionary *(^RDNMFreshReader)(NSArray *entries,NSString **error);
typedef BOOL (^RDNMCommitter)(NSArray *entries,RDNativeModeRequest request,BOOL restoring,NSDictionary *freshCurrent,BOOL *committed);
typedef NS_ENUM(NSUInteger,RDNMRecoveryFailure) {RDNMRecoveryFailureNone=0,RDNMRecoveryFailureStop=1,RDNMRecoveryFailureTargetRejectedRestored=2};
// Decision engine: the entry.before snapshot is immutable across bridge and
// final stages. Only an independently confirmed original mode permits retry.
static inline BOOL RDNMApplyPlanWithReadersWithFailure(NSDictionary *plan,RDNMFreshReader reader,RDNMCommitter commit,RDNMRecoveryFailure *failure,NSString **error) {
    if(failure)*failure=RDNMRecoveryFailureStop;
    NSArray *entries=plan[@"entries"];RDNativeModeRequest request=RDNMRequestFromInfo(plan[@"request"]);
    if(!entries.count||entries.count>64||!RDNativeRequestValid(request))return RDNMFail(error,@"原生显示计划无效。");
    NSString *readError=nil;NSDictionary *current=reader(entries,&readError);
    if(!current)return RDNMFail(error,[NSString stringWithFormat:@"无法独立确认事务前模式；未应用。%@",readError?:@""]);
    if(!RDNMFreshMatches(current,entries,request,YES))return RDNMFail(error,@"应用前独立读回与原模式不同；未覆盖外部更改。");
    if(RDNMFreshMatches(current,entries,request,NO)){if(failure)*failure=RDNMRecoveryFailureNone;return YES;}
    NSDictionary *bridge=RDNMBridgeRequest(plan);
    if(plan[@"bridgeRequest"]) {
        if(!bridge||!RDNativeRequestsMatch(RDNMRequestFromInfo(bridge),RDNMRequestFromInfo(plan[@"bridgeRequest"])))return RDNMFail(error,@"桥接计划的精确模式或独立单屏计数无效；未应用。");
        if(!RDNMFreshSingleOnlineTarget(current,entries))return RDNMFail(error,@"桥接前未独立确认仅一个在线显示器；未应用。");
    } else bridge=nil;
    NSArray *phases=bridge?@[bridge,plan[@"request"]]:@[plan[@"request"]];BOOL bridgeConfirmed=NO;
    for(NSUInteger index=0;index<phases.count;index++) {
        RDNativeModeRequest phase=RDNMRequestFromInfo(phases[index]);BOOL bridging=bridge&&index==0;
        if(index) {
            // A second observation before the final stage refuses an external
            // change after bridge confirmation rather than overwriting it.
            current=reader(entries,&readError);
            if(!current)return RDNMFail(error,[NSString stringWithFormat:@"桥接后无法独立确认状态；未继续配置或回滚。%@",readError?:@""]);
            if(!RDNMFreshSingleOnlineTarget(current,entries))return RDNMFail(error,@"桥接后的在线显示器计数缺失或变化；未继续配置或回滚。");
            if(RDNMFreshMatches(current,entries,request,NO)){if(failure)*failure=RDNMRecoveryFailureNone;return YES;}
            if(!RDNMFreshMatches(current,entries,RDNMRequestFromInfo(bridge),NO))return RDNMFail(error,@"桥接后显示状态已外部变化；未覆盖或回滚该变化。");
        }
        BOOL committed=NO;BOOL accepted=commit(entries,phase,NO,current,&committed);(void)committed;
        NSDictionary *after=reader(entries,&readError);
        if(!after)return RDNMFail(error,[NSString stringWithFormat:@"提交后无法独立确认当前设置；未自动回滚，避免覆盖未知状态。%@",readError?:@""]);
        if(bridge&&!RDNMFreshSingleOnlineTarget(after,entries))return RDNMFail(error,@"桥接阶段的在线显示器计数缺失或变化；未自动回滚。");
        if(RDNMFreshMatches(after,entries,request,NO)){if(failure)*failure=RDNMRecoveryFailureNone;return YES;}
        if(bridging&&RDNMFreshMatches(after,entries,phase,NO)){bridgeConfirmed=YES;current=after;continue;}
        NSString *stage=bridging?@"公开1×桥接":@"目标模式";
        NSString *detail=[NSString stringWithFormat:@"%@未通过独立校验（API accepted=%@）。",stage,accepted?@"YES":@"NO"];
        if(RDNMFreshMatches(after,entries,request,YES)) {
            if(failure)*failure=RDNMRecoveryFailureTargetRejectedRestored;
            return RDNMFail(error,[detail stringByAppendingString:@"当前设置已核对与操作前一致；未追加回滚写入。"]);
        }
        if(!bridgeConfirmed||!RDNMFreshMatches(after,entries,RDNMRequestFromInfo(bridge),NO))return RDNMFail(error,[detail stringByAppendingString:@"读回为第三种设置，可能来自外部变化；保留当前状态，未自动回滚。"]);
        BOOL rollbackCommitted=NO;commit(entries,request,YES,after,&rollbackCommitted);
        NSDictionary *restored=reader(entries,&readError);
        if(!restored)return RDNMFail(error,[NSString stringWithFormat:@"%@已请求回退操作前设置，但独立读回无法确认结果。%@",detail,readError?:@""]);
        if(!RDNMFreshSingleOnlineTarget(restored,entries))return RDNMFail(error,@"回退后的在线显示器计数缺失或变化；无法确认结果。");
        BOOL confirmed=RDNMFreshMatches(restored,entries,request,YES);
        if(confirmed&&failure)*failure=RDNMRecoveryFailureTargetRejectedRestored;
        return RDNMFail(error,[detail stringByAppendingString:confirmed?@"当前设置已核对与操作前一致。":@"当前设置未确认与操作前一致；请检查系统显示设置。"]);
    }
    return RDNMFail(error,@"原生显示阶段未完成；未报告成功。");
}
static inline BOOL RDNMApplyPlanWithReaders(NSDictionary *plan,RDNMFreshReader reader,RDNMCommitter commit,NSString **error) {
    return RDNMApplyPlanWithReadersWithFailure(plan,reader,commit,NULL,error);
}
static inline BOOL RDApplyHiddenNativeModePlanWithFailure(NSDictionary *plan,RDNMRecoveryFailure *failure,NSString **error) {
    NSMutableArray *diagnostics=[NSMutableArray array];BOOL hasBridge=plan[@"bridgeRequest"]!=nil;
    BOOL ok=RDNMApplyPlanWithReadersWithFailure(plan,^NSDictionary *(NSArray *entries,NSString **readError){
        NSDictionary *fresh=RDNMReadFreshState(entries,readError);
        if(hasBridge&&fresh&&!RDNMFreshSingleOnlineTarget(fresh,entries)){RDNMFail(readError,@"桥接显示拓扑未独立确认仅一个在线显示器；未继续配置。");return nil;}
        return fresh;
    },^BOOL(NSArray *entries,RDNativeModeRequest request,BOOL restoring,NSDictionary *current,BOOL *committed){
        BOOL publicOnly=hasBridge&&!restoring&&RDNativeRequestsMatch(request,RDNMRequestFromInfo(plan[@"bridgeRequest"]));NSString *status=nil;
        BOOL accepted=RDNMTransactionWithStatus(entries,request,restoring,current,committed,publicOnly,&status);
        if(status)[diagnostics addObject:[NSString stringWithFormat:@"%@ %@",restoring?@"rollback":(publicOnly?@"bridge":@"target"),status]];return accepted;
    },failure,error);
    if(!ok&&error&&diagnostics.count)*error=[NSString stringWithFormat:@"%@ %@",*error?:@"原生显示恢复失败。",[diagnostics componentsJoinedByString:@"; "]];
    return ok;
}
static inline BOOL RDApplyHiddenNativeModePlan(NSDictionary *plan,NSString **error) {
    return RDApplyHiddenNativeModePlanWithFailure(plan,NULL,error);
}
static inline BOOL RDApplyHiddenNativeModesWithFailure(NSArray<NSNumber *> *ids,NSUInteger width,NSUInteger height,NSUInteger pixelWidth,NSUInteger pixelHeight,double rate,RDNMRecoveryFailure *failure,NSString **error) {
    if(failure)*failure=RDNMRecoveryFailureStop;NSDictionary *plan=RDHiddenNativeModePlan(ids,width,height,pixelWidth,pixelHeight,rate,error);
    return plan&&RDApplyHiddenNativeModePlanWithFailure(plan,failure,error);
}
static inline BOOL RDApplyHiddenNativeModes(NSArray<NSNumber *> *ids,NSUInteger width,NSUInteger height,NSUInteger pixelWidth,NSUInteger pixelHeight,double rate,NSString **error) {
    return RDApplyHiddenNativeModesWithFailure(ids,width,height,pixelWidth,pixelHeight,rate,NULL,error);
}

static inline BOOL RDNMPlanStructureValid(NSDictionary *plan) {
    if(![plan isKindOfClass:NSDictionary.class]||![plan[@"request"] isKindOfClass:NSDictionary.class]
      ||!RDNativeRequestValid(RDNMRequestFromInfo(plan[@"request"]))||![plan[@"entries"] isKindOfClass:NSArray.class]
      ||![plan[@"entries"] count]||[plan[@"entries"] count]>64)return NO;
    NSMutableSet *seen=[NSMutableSet set];
    for(id entry in plan[@"entries"]) {
        if(![entry isKindOfClass:NSDictionary.class]||!RDNMJSONNumber(entry[@"displayID"])
          ||[entry[@"displayID"] doubleValue]<1||[entry[@"displayID"] doubleValue]>UINT32_MAX
          ||floor([entry[@"displayID"] doubleValue])!=[entry[@"displayID"] doubleValue]
          ||[seen containsObject:entry[@"displayID"]]||![entry[@"identity"] isKindOfClass:NSDictionary.class]
          ||![entry[@"identity"][@"uuid"] isKindOfClass:NSString.class]
          ||![[NSUUID alloc] initWithUUIDString:entry[@"identity"][@"uuid"]]
          ||![entry[@"before"] isKindOfClass:NSDictionary.class]||!RDNativeRequestValid(RDNMRequestFromInfo(entry[@"before"])))return NO;
        [seen addObject:entry[@"displayID"]];
    }
    return YES;
}
static inline NSDictionary *RDNMReadPinnedPlanState(NSDictionary *plan,NSString **error) {
    if(!RDNMPlanStructureValid(plan)){RDNMFail(error,@"原生显示计划无效。");return nil;}
    NSArray *entries=plan[@"entries"];
    for(NSDictionary *entry in entries)if(!RDNMIdentityMatches(entry)){RDNMFail(error,@"显示身份或非镜像拓扑已变化；未确认当前设置。");return nil;}
    NSDictionary *fresh=RDNMReadFreshState(entries,error);if(!fresh)return nil;
    for(NSDictionary *entry in entries)if(!RDNMIdentityMatches(entry)){RDNMFail(error,@"独立读回期间显示身份已变化；未确认当前设置。");return nil;}
    if(plan[@"bridgeRequest"]&&!RDNMFreshSingleOnlineTarget(fresh,entries)){RDNMFail(error,@"桥接计划的单屏拓扑未获独立确认。");return nil;}
    return fresh;
}
static inline BOOL RDNMPlanTargetIsCurrentWithReader(NSDictionary *plan,RDNMFreshReader reader,NSString **error) {
    if(!RDNMPlanStructureValid(plan))return RDNMFail(error,@"原生显示计划无效。");
    NSDictionary *fresh=reader(plan[@"entries"],error);if(!fresh)return NO;
    if(plan[@"bridgeRequest"]&&!RDNMFreshSingleOnlineTarget(fresh,plan[@"entries"]))return RDNMFail(error,@"单屏拓扑未获独立确认。");
    return RDNMFreshMatches(fresh,plan[@"entries"],RDNMRequestFromInfo(plan[@"request"]),NO)||RDNMFail(error,@"当前设置未独立确认等于本次目标。");
}
static inline BOOL RDNativePlanTargetIsCurrent(NSDictionary *plan,NSString **error) {
    return RDNMPlanTargetIsCurrentWithReader(plan,^NSDictionary *(NSArray *entries,NSString **readError){(void)entries;return RDNMReadPinnedPlanState(plan,readError);},error);
}

typedef NSDictionary *(^RDNMOriginalPlanBuilder)(NSNumber *display,RDNativeModeRequest original,NSString **error);
typedef BOOL (^RDNMOriginalPlanApplier)(NSDictionary *reversePlan,NSString **error);
// The UI must bind cancellation to this immutable plan and its own generation.
// A failed reverse attempt is allowed to preserve the selected target, but must
// never report that the original setting was restored unless fresh reads agree.
static inline BOOL RDNMRestoreNativePlanOriginalWithReaders(NSDictionary *plan,RDNMFreshReader reader,RDNMOriginalPlanBuilder builder,RDNMOriginalPlanApplier apply,NSString **error) {
    if(!RDNMPlanStructureValid(plan)||[plan[@"entries"] count]!=1)return RDNMFail(error,@"取消恢复仅支持单个已锁定的实体屏计划。");
    NSArray *entries=plan[@"entries"];NSDictionary *entry=entries[0];RDNativeModeRequest target=RDNMRequestFromInfo(plan[@"request"]),original=RDNMRequestFromInfo(entry[@"before"]);
    NSDictionary *current=reader(entries,error);if(!current)return NO;
    if(plan[@"bridgeRequest"]&&!RDNMFreshSingleOnlineTarget(current,entries))return RDNMFail(error,@"取消前单屏拓扑未获独立确认；未配置。");
    if(RDNMFreshMatches(current,entries,target,YES))return YES;
    if(!RDNMFreshMatches(current,entries,target,NO))return RDNMFail(error,@"取消时设置已不等于本次目标；未覆盖外部状态。");
    NSDictionary *reverse=builder(entry[@"displayID"],original,error);
    if(!RDNMPlanStructureValid(reverse)||[reverse[@"entries"] count]!=1)return RDNMFail(error,@"无法生成精确的反向恢复计划；未配置。");
    NSDictionary *reverseEntry=reverse[@"entries"][0];
    if(![reverseEntry[@"displayID"] isEqual:entry[@"displayID"]]||![reverseEntry[@"identity"] isEqual:entry[@"identity"]]
      ||!RDNativeRequestsMatch(RDNMRequestFromInfo(reverse[@"request"]),original)
      ||!RDNativeRequestsMatch(RDNMRequestFromInfo(reverseEntry[@"before"]),target))return RDNMFail(error,@"反向计划的身份、目标或操作前设置已变化；未配置。");
    current=reader(entries,error);if(!current)return NO;
    if(plan[@"bridgeRequest"]&&!RDNMFreshSingleOnlineTarget(current,entries))return RDNMFail(error,@"取消期间单屏拓扑已变化；未配置。");
    if(RDNMFreshMatches(current,entries,target,YES))return YES;
    if(!RDNMFreshMatches(current,entries,target,NO))return RDNMFail(error,@"反向应用前状态已外部变化；未覆盖。");
    NSString *applyError=nil;BOOL accepted=apply(reverse,&applyError);(void)accepted;
    NSDictionary *after=reader(entries,error);if(!after)return RDNMFail(error,@"取消后无法独立确认设置；未追加配置。");
    if(plan[@"bridgeRequest"]&&!RDNMFreshSingleOnlineTarget(after,entries))return RDNMFail(error,@"取消后的单屏拓扑未获独立确认。");
    if(RDNMFreshMatches(after,entries,target,YES))return YES;
    return RDNMFail(error,[NSString stringWithFormat:@"取消恢复未获独立确认；未报告原设置已恢复。%@",applyError?:@""]);
}
static inline BOOL RDRestoreNativePlanOriginal(NSDictionary *plan,NSString **error) {
    return RDNMRestoreNativePlanOriginalWithReaders(plan,^NSDictionary *(NSArray *entries,NSString **readError){(void)entries;return RDNMReadPinnedPlanState(plan,readError);},
        ^NSDictionary *(NSNumber *display,RDNativeModeRequest original,NSString **planError){return RDHiddenNativeModePlan(@[display],original.width,original.height,original.pixelWidth,original.pixelHeight,original.rate,planError);},
        ^BOOL(NSDictionary *reverse,NSString **applyError){return RDApplyHiddenNativeModePlan(reverse,applyError);},error);
}
