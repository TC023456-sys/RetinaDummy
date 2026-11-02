#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ColorSync/ColorSync.h>
#import <CoreVideo/CoreVideo.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// Short-lived observer. This executable never configures a display, starts
// another application, or sends a signal. Its fresh CG client avoids trusting
// the configuring process's potentially stale display cache.
static NSDictionary *RDDSIssue(NSUInteger index,NSNumber *display,NSString *code,NSString *message) {
    NSMutableDictionary *issue=[@{@"index":@(index),@"code":code,@"message":message} mutableCopy];
    if(display)issue[@"displayID"]=display;
    return issue;
}
static NSArray<NSDictionary *> *RDDSParseTargets(NSData *data,NSMutableArray *errors) {
    if(!data.length||data.length>16384){[errors addObject:RDDSIssue(0,nil,@"InvalidInput",@"Target JSON is empty or exceeds 16 KiB.")];return nil;}
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![value isKindOfClass:NSArray.class]||![value count]||[value count]>64){[errors addObject:RDDSIssue(0,nil,@"InvalidTargets",@"Expected an array containing 1 to 64 targets.")];return nil;}
    NSMutableArray *targets=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];
    for(NSUInteger index=0;index<[value count];index++) {
        id item=value[index];
        if(![item isKindOfClass:NSDictionary.class]){[errors addObject:RDDSIssue(index,nil,@"InvalidTarget",@"Each target must be an object.")];continue;}
        id number=item[@"displayID"],uuidString=item[@"uuid"];
        BOOL validID=[number isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)number)!=CFBooleanGetTypeID();
        double numeric=validID?[number doubleValue]:0;
        validID=validID&&isfinite(numeric)&&numeric>=1&&numeric<=UINT32_MAX&&floor(numeric)==numeric;
        if(!validID){[errors addObject:RDDSIssue(index,nil,@"InvalidDisplayID",@"displayID must be an integer from 1 through UINT32_MAX.")];continue;}
        NSNumber *display=@((uint32_t)numeric);
        NSUUID *uuid=[uuidString isKindOfClass:NSString.class]&&[uuidString length]==36?[[NSUUID alloc] initWithUUIDString:uuidString]:nil;
        if(!uuid){[errors addObject:RDDSIssue(index,display,@"InvalidUUID",@"uuid must be a complete display UUID.")];continue;}
        if([seen containsObject:display]){[errors addObject:RDDSIssue(index,display,@"DuplicateTarget",@"A displayID may appear only once.")];continue;}
        [seen addObject:display];[targets addObject:@{@"displayID":display,@"uuid":uuid.UUIDString}];
    }
    return errors.count?nil:targets;
}
static NSString *RDDSUUID(CGDirectDisplayID display) {
    CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);if(!uuid)return nil;
    NSString *text=CFBridgingRelease(CFUUIDCreateString(NULL,uuid));CFRelease(uuid);return text;
}
// A mode record alone does not establish the desktop's logical geometry.
// Refuse inconsistent observations instead of using them to change a display.
static BOOL RDDSModeMatchesBounds(size_t width,size_t height,CGRect bounds,double rotation) {
    if(!width||!height||CGRectIsNull(bounds)||CGRectIsInfinite(bounds)
       ||!isfinite(bounds.origin.x)||!isfinite(bounds.origin.y)
       ||!isfinite(bounds.size.width)||!isfinite(bounds.size.height)
       ||bounds.size.width<=0||bounds.size.height<=0||!isfinite(rotation))return NO;
    double angle=fmod(fmod(rotation,360.0)+360.0,360.0);
    BOOL swapped=fabs(angle-90.0)<0.01||fabs(angle-270.0)<0.01;
    if(!swapped&&fabs(angle)>0.01&&fabs(angle-180.0)>0.01)return NO;
    BOOL same=fabs(bounds.size.width-width)<0.5&&fabs(bounds.size.height-height)<0.5;
    BOOL transposed=fabs(bounds.size.width-height)<0.5&&fabs(bounds.size.height-width)<0.5;
    // For quarter-turns, accept either orientation of the same size pair.
    return same||(swapped&&transposed);
}
typedef struct { CGDirectDisplayID display;CGRect frame;double scale;CGRect backing; } RDDSScreenSample;
static BOOL RDDSScreenGeometryValid(CGDirectDisplayID display,CGRect bounds,double rotation,RDDSScreenSample screen) {
    if(!display||screen.display!=display||!isfinite(rotation))return NO;
    double angle=fmod(fmod(rotation,360.0)+360.0,360.0);
    if(fabs(angle)>0.01&&fabs(angle-180.0)>0.01)return NO; // Other rotations remain unknown.
    if(CGRectIsNull(bounds)||CGRectIsInfinite(bounds)||CGRectIsNull(screen.frame)||CGRectIsInfinite(screen.frame)
      ||CGRectIsNull(screen.backing)||CGRectIsInfinite(screen.backing)||!isfinite(screen.scale)||screen.scale<1||screen.scale>4)return NO;
    double values[]={bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height,screen.frame.origin.x,screen.frame.origin.y,
        screen.frame.size.width,screen.frame.size.height,screen.backing.origin.x,screen.backing.origin.y,screen.backing.size.width,screen.backing.size.height};
    for(NSUInteger i=0;i<sizeof(values)/sizeof(values[0]);i++)if(!isfinite(values[i]))return NO;
    // AppKit and CG use different global origins. Compare their sizes only.
    if(fabs(screen.frame.size.width-bounds.size.width)>=0.01||fabs(screen.frame.size.height-bounds.size.height)>=0.01)return NO;
    double sizes[]={screen.frame.size.width,screen.frame.size.height,screen.backing.size.width,screen.backing.size.height};
    for(NSUInteger i=0;i<4;i++)if(sizes[i]<1||sizes[i]>32768||fabs(sizes[i]-round(sizes[i]))>=0.01)return NO;
    return fabs(screen.backing.size.width-screen.frame.size.width*screen.scale)<0.5
        &&fabs(screen.backing.size.height-screen.frame.size.height*screen.scale)<0.5;
}
static BOOL RDDSNominalPairValid(CGDirectDisplayID display,CGDirectDisplayID before,CGDirectDisplayID after,CVTime a,CVTime b,BOOL running,double *hz) {
    if(hz)*hz=0;
    if(!display||before!=display||after!=display||running||a.flags!=0||b.flags!=0||a.timeValue<=0||a.timeScale<=0
      ||a.timeValue!=b.timeValue||a.timeScale!=b.timeScale)return NO;
    double value=(double)a.timeScale/(double)a.timeValue;
    if(!isfinite(value)||value<1||value>1000)return NO;
    if(hz)*hz=value;return YES;
}
static NSDictionary *RDDSFallbackMode(CGDirectDisplayID display,CGRect bounds,double rotation,RDDSScreenSample screen,
    CGDirectDisplayID before,CGDirectDisplayID after,CVTime a,CVTime b,BOOL running) {
    double hz=0;
    if(!RDDSScreenGeometryValid(display,bounds,rotation,screen)||!RDDSNominalPairValid(display,before,after,a,b,running,&hz))return nil;
    return @{@"width":@(llround(screen.frame.size.width)),@"height":@(llround(screen.frame.size.height)),
        @"pixelWidth":@(llround(screen.backing.size.width)),@"pixelHeight":@(llround(screen.backing.size.height)),@"hz":@(hz),
        @"geometrySource":@"NSScreenFrameAndBacking",@"refreshSource":@"CVDisplayLinkNominal",
        @"refreshInterpretation":@"Device ideal refresh period metadata; not measured physical scanout.",
        @"nominalTimeValue":@(a.timeValue),@"nominalTimeScale":@(a.timeScale)};
}
static BOOL RDDSScreenSamplesEqual(RDDSScreenSample a,RDDSScreenSample b) {
    return a.display==b.display&&CGRectEqualToRect(a.frame,b.frame)&&a.scale==b.scale&&CGRectEqualToRect(a.backing,b.backing);
}
static BOOL RDDSReadScreen(CGDirectDisplayID display,RDDSScreenSample *sample) {
    for(NSScreen *screen in NSScreen.screens) {
        NSNumber *number=screen.deviceDescription[@"NSScreenNumber"];
        if(number.unsignedIntValue!=display)continue;
        NSRect frame=screen.frame,backing=[screen convertRectToBacking:NSMakeRect(0,0,frame.size.width,frame.size.height)];
        *sample=(RDDSScreenSample){display,frame,screen.backingScaleFactor,backing};return YES;
    }
    return NO;
}
static NSDictionary *RDDSReadFallback(CGDirectDisplayID display,CGRect bounds,double rotation,RDDSScreenSample *sample) {
    double angle=fmod(fmod(rotation,360.0)+360.0,360.0);
    if(!isfinite(rotation)||(fabs(angle)>0.01&&fabs(angle-180.0)>0.01))return nil;
    // Establish the documented AppKit connection only for this fallback. This
    // process never runs/activates the application or creates any windows.
    NSApplication *application=NSApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
    // An already-prohibited CLI can return NO for the redundant setter.
    if(application.activationPolicy!=NSApplicationActivationPolicyProhibited)return nil;
    if(!RDDSReadScreen(display,sample)||!RDDSScreenGeometryValid(display,bounds,rotation,*sample))return nil;
    CVDisplayLinkRef link=NULL;CVTime a={0},b={0};CGDirectDisplayID before=0,after=0;BOOL running=YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CVReturn status=CVDisplayLinkCreateWithCGDisplay(display,&link);
    if(status==kCVReturnSuccess&&link) {
        before=CVDisplayLinkGetCurrentCGDisplay(link);running=CVDisplayLinkIsRunning(link);
        a=CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link);b=CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link);
        after=CVDisplayLinkGetCurrentCGDisplay(link);running|=CVDisplayLinkIsRunning(link);
    }
    if(link)CVDisplayLinkRelease(link); // Never started, no callback; release immediately after two reads.
#pragma clang diagnostic pop
    return status==kCVReturnSuccess?RDDSFallbackMode(display,bounds,rotation,*sample,before,after,a,b,running):nil;
}
static NSDictionary *RDDSReadTargets(NSArray<NSDictionary *> *targets) {
    NSMutableArray *observations=[NSMutableArray array],*errors=[NSMutableArray array];
    // Prime this process's CG client before UUID and individual display queries.
    uint32_t capacity=0;CGError status=CGGetOnlineDisplayList(0,NULL,&capacity);
    if(status!=kCGErrorSuccess||capacity>4096){[errors addObject:RDDSIssue(0,nil,@"OnlineListUnavailable",@"Cannot enumerate the online display list.")];return @{@"schemaVersion":@1,@"observations":observations,@"errors":errors};}
    CGDirectDisplayID *displays=capacity?calloc(capacity,sizeof(*displays)):NULL;
    uint32_t count=0;
    if(capacity&&!displays)status=kCGErrorFailure;
    else if(capacity)status=CGGetOnlineDisplayList(capacity,displays,&count);
    NSMutableSet *online=[NSMutableSet set];
    for(uint32_t i=0;status==kCGErrorSuccess&&i<count&&i<capacity;i++)[online addObject:@(displays[i])];
    free(displays);
    if(status!=kCGErrorSuccess||count>capacity){[errors addObject:RDDSIssue(0,nil,@"OnlineListUnavailable",@"Cannot read a complete online display list.")];return @{@"schemaVersion":@1,@"observations":observations,@"errors":errors};}
    for(NSUInteger index=0;index<targets.count;index++) {
        NSDictionary *target=targets[index];NSNumber *number=target[@"displayID"];CGDirectDisplayID display=number.unsignedIntValue;
        if(![online containsObject:number]||!CGDisplayIsOnline(display)){[errors addObject:RDDSIssue(index,number,@"Offline",@"The requested display is not online.")];continue;}
        NSString *uuid=RDDSUUID(display);
        if(!uuid||[uuid caseInsensitiveCompare:target[@"uuid"]]!=NSOrderedSame){[errors addObject:RDDSIssue(index,number,@"UUIDMismatch",@"The online display UUID does not match the requested UUID.")];continue;}
        if(CGDisplayMirrorsDisplay(display)||CGDisplayIsInMirrorSet(display)){[errors addObject:RDDSIssue(index,number,@"Mirrored",@"The requested display is part of a mirror set.")];continue;}
        CGRect bounds=CGDisplayBounds(display);double rotation=CGDisplayRotation(display);
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(display);
        if(!mode){[errors addObject:RDDSIssue(index,number,@"ModeUnavailable",@"The current display mode is unavailable.")];continue;}
        size_t w=CGDisplayModeGetWidth(mode),h=CGDisplayModeGetHeight(mode),pw=CGDisplayModeGetPixelWidth(mode),ph=CGDisplayModeGetPixelHeight(mode);double hz=CGDisplayModeGetRefreshRate(mode);
        CFRelease(mode);
        NSDictionary *fallback=nil;RDDSScreenSample screenBefore={0};
        if(RDDSModeMatchesBounds(w,h,bounds,rotation)) {
            if(!w||!h||!pw||!ph||!isfinite(hz)||hz<0){[errors addObject:RDDSIssue(index,number,@"InvalidMode",@"The current mode has invalid geometry or refresh rate.")];continue;}
        } else {
            fallback=RDDSReadFallback(display,bounds,rotation,&screenBefore);
            if(!fallback){[errors addObject:RDDSIssue(index,number,@"GeometryMismatch",@"Mode/bounds disagree and independent Cocoa geometry with valid CoreVideo nominal refresh could not be confirmed.")];continue;}
        }
        NSMutableDictionary *observation=[@{@"displayID":number,@"uuid":uuid,@"online":@YES,@"mirrored":@NO,@"width":@(w),@"height":@(h),@"pixelWidth":@(pw),@"pixelHeight":@(ph),@"hz":@(hz),@"boundsWidth":@(bounds.size.width),@"boundsHeight":@(bounds.size.height),@"rotation":@(rotation),@"onlineDisplayCount":@(online.count)} mutableCopy];
        if(fallback) {
            RDDSScreenSample screenAfter={0};
            if(!RDDSReadScreen(display,&screenAfter)||!RDDSScreenSamplesEqual(screenBefore,screenAfter)||!RDDSScreenGeometryValid(display,bounds,rotation,screenAfter)) {
                [errors addObject:RDDSIssue(index,number,@"StateChanged",@"NSScreen frame, backing scale or backing conversion changed during observation.")];continue;
            }
            observation[@"cgReportedWidth"]=@(w);observation[@"cgReportedHeight"]=@(h);
            observation[@"cgReportedPixelWidth"]=@(pw);observation[@"cgReportedPixelHeight"]=@(ph);
            [observation addEntriesFromDictionary:fallback];
        }
        // Refuse a mixed identity/topology snapshot if the connection moved.
        NSString *afterUUID=RDDSUUID(display);double afterRotation=CGDisplayRotation(display);
        if(!CGDisplayIsOnline(display)||!afterUUID||[afterUUID caseInsensitiveCompare:uuid]!=NSOrderedSame||CGDisplayMirrorsDisplay(display)||CGDisplayIsInMirrorSet(display)||!CGRectEqualToRect(bounds,CGDisplayBounds(display))||!isfinite(afterRotation)||fabs(rotation-afterRotation)>0.01){[errors addObject:RDDSIssue(index,number,@"StateChanged",@"Display identity, mirroring or desktop geometry changed during observation.")];continue;}
        [observations addObject:observation];
    }
    return @{@"schemaVersion":@1,@"observations":observations,@"errors":errors};
}
static int RDDSEmit(NSDictionary *result,int code) {
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
    if(!json||json.length>=16384){result=@{@"schemaVersion":@1,@"observations":@[],@"errors":@[RDDSIssue(0,nil,@"OutputLimit",@"The observation result exceeds the output limit.")]};json=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];code=70;}
    fwrite(json.bytes,1,json.length,stdout);putchar('\n');return code;
}
#ifndef RD_DISPLAY_STATE_HELPER_TEST
int main(int argc,const char *argv[]) { @autoreleasepool {
    NSMutableArray *errors=[NSMutableArray array];
    if(argc!=3||strcmp(argv[1],"--read-state")||strnlen(argv[2],16385)>16384){[errors addObject:RDDSIssue(0,nil,@"Usage",@"Usage: RetinaDisplayState --read-state '[{displayID,uuid}]'")];return RDDSEmit(@{@"schemaVersion":@1,@"observations":@[],@"errors":errors},64);}
    NSData *data=[[NSString stringWithUTF8String:argv[2]] dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *targets=RDDSParseTargets(data,errors);
    if(!targets)return RDDSEmit(@{@"schemaVersion":@1,@"observations":@[],@"errors":errors},64);
    NSDictionary *result=RDDSReadTargets(targets);
    return RDDSEmit(result,[result[@"errors"] count]?2:0);
} }
#endif
