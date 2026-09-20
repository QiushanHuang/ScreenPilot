// Bounded feasibility probe. No DDC calls. Session-only display configuration.
@import Foundation;
@import CoreGraphics;
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include "ControlSafety.h"
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);
typedef CGError (*ConfigureEnabled)(CGDisplayConfigRef,CGDirectDisplayID,bool);
static void output(id value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes,1,data.length,stdout); puts("");
}
static NSString *uuidFor(CGDirectDisplayID display) {
    NSDictionary *info=CFBridgingRelease(CoreDisplay_DisplayCreateInfoDictionary(display));
    id uuid=info[@"kCGDisplayUUID"];
    return [uuid isKindOfClass:[NSString class]] ? uuid : @"";
}
static NSString *bootID(void) {
    char value[128]={0}; size_t len=sizeof(value);
    if(sysctlbyname("kern.bootsessionuuid",value,&len,NULL,0)) return @"";
    return @(value);
}
static NSArray *snapshot(void) {
    CGDirectDisplayID ids[32]; uint32_t count=0; CGGetOnlineDisplayList(32,ids,&count);
    NSMutableArray *displays=[NSMutableArray array];
    for(uint32_t i=0;i<count;i++) {
        CGDirectDisplayID d=ids[i]; CGRect rect=CGDisplayBounds(d); CGDisplayModeRef mode=CGDisplayCopyDisplayMode(d);
        [displays addObject:@{@"id":@(d),@"uuid":uuidFor(d),@"active":@(CGDisplayIsActive(d)),@"main":@(CGDisplayIsMain(d)),
          @"x":@(rect.origin.x),@"y":@(rect.origin.y),@"width":@(rect.size.width),@"height":@(rect.size.height),
          @"rotation":@(CGDisplayRotation(d)),@"mode":@(mode?CGDisplayModeGetIODisplayModeID(mode):0),@"mirrors":@(CGDisplayMirrorsDisplay(d))}];
        if(mode) CGDisplayModeRelease(mode);
    }
    return displays;
}
static int failure(NSString *message) { output(@{@"ok":@NO,@"error":message}); return 1; }
int main(int argc,const char *argv[]) { @autoreleasepool {
    if(argc<2) return failure(@"Expected snapshot / capture / disable / restore");
    NSString *command=@(argv[1]);
    if([command isEqual:@"inspect"]) { NSMutableArray *rows=[NSMutableArray array]; for(CGDirectDisplayID d=1;d<=4;d++) [rows addObject:@{@"id":@(d),@"uuid":uuidFor(d),@"active":@(CGDisplayIsActive(d)),@"online":@(CGDisplayIsOnline(d))}]; output(rows); return 0; }
    if([command isEqual:@"snapshot"]) { output(@{@"ok":@YES,@"displays":snapshot()}); return 0; }
    if(argc<3) return failure(@"Missing lease file");
    NSString *file=@(argv[2]);
    if([command isEqual:@"capture"]) {
        if([[NSFileManager defaultManager] fileExistsAtPath:file]) return failure(@"Lease exists; use a new file");
        NSString *boot=bootID(); if(!boot.length) return failure(@"No boot session identity");
        NSDictionary *lease=@{@"created":@([NSDate date].timeIntervalSince1970),@"boot":boot,@"displays":snapshot()};
        NSData *data=[NSJSONSerialization dataWithJSONObject:lease options:NSJSONWritingPrettyPrinted error:nil];
        if(![[NSFileManager defaultManager] createFileAtPath:file contents:data attributes:@{NSFilePosixPermissions:@0600}]) return failure(@"Cannot save recovery lease");
        output(@{@"ok":@YES,@"lease":file}); return 0;
    }
    NSData *data=[NSData dataWithContentsOfFile:file];
    NSDictionary *lease=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![lease isKindOfClass:[NSDictionary class]] || ![lease[@"boot"] isEqual:bootID()] || [NSDate date].timeIntervalSince1970-[lease[@"created"] doubleValue]>300)
        return failure(@"Missing, stale or different-boot recovery lease");
    NSArray *saved=lease[@"displays"];
    if(![saved isKindOfClass:[NSArray class]] || saved.count<2 || saved.count>32) return failure(@"Invalid display snapshot");
    void *library=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
    ConfigureEnabled configure=library?(ConfigureEnabled)dlsym(library,"SLSConfigureDisplayEnabled"):NULL;
    if(!configure && library) configure=(ConfigureEnabled)dlsym(library,"CGSConfigureDisplayEnabled");
    if(!configure) return failure(@"No display enable API");
    NSDictionary *target=nil;
    BOOL disabling=[command isEqual:@"disable"] || [command isEqual:@"validate-disable"];
    BOOL enabling=[command isEqual:@"enable"];
    BOOL partialLayout=[command isEqual:@"layout-active"];
    if(disabling || enabling) {
        if(argc!=4) return failure(@"Missing UUID");
        for(NSDictionary *d in saved) if([d[@"uuid"] isEqual:@(argv[3])]) { if(target) return failure(@"Duplicate UUID"); target=d; }
        if(!target || [target[@"mirrors"] unsignedIntValue]) return failure(@"Target is missing or mirrored");
        CGDirectDisplayID targetID=[target[@"id"] unsignedIntValue];
        uint32_t active=0; CGGetActiveDisplayList(0,NULL,&active);
        if(disabling && !canDisableDisplay(active,CGDisplayIsActive(targetID),[uuidFor(targetID) isEqual:target[@"uuid"]])) return failure(@"Target changed or last active screen");
        if(enabling) {
            NSString *actual=uuidFor(targetID);
            if(!canRestoreCachedDisplay([lease[@"boot"] isEqual:bootID()],[actual isEqual:target[@"uuid"]],!actual.length || [actual isEqual:@"00000000-0000-0000-0000-000000000000"],CGDisplayIsOnline(targetID),CGDisplayIsActive(targetID))) return failure(@"Target identity changed");
            if(CGDisplayIsActive(targetID)) { output(@{@"ok":@YES,@"displays":snapshot()}); return 0; }
        }
        if([command isEqual:@"validate-disable"]) { output(@{@"ok":@YES,@"displays":snapshot()}); return 0; }
    } else if(![command isEqual:@"restore"] && !partialLayout) return failure(@"Unknown command");
    int lockFD=open([[file stringByAppendingString:@".lock"] fileSystemRepresentation],O_CREAT|O_RDWR,0600);
    if(lockFD<0 || flock(lockFD,LOCK_EX)) return failure(@"Cannot lock display transaction");
    NSString *restoringMarker=[[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"restoring"];
    if(disabling && [[NSFileManager defaultManager] fileExistsAtPath:restoringMarker]) return failure(@"Recovery is in progress");
    BOOL restoringOffline=NO;
    if(!target && !partialLayout) for(NSDictionary *d in saved) if([d[@"active"] boolValue] && !CGDisplayIsActive([d[@"id"] unsignedIntValue])) restoringOffline=YES;
    CGDisplayConfigRef config=NULL; CGError e=CGBeginDisplayConfiguration(&config);
    if(e || !config) return failure(@"Cannot begin display transaction");
    if(target) {
        e=configure(config,[target[@"id"] unsignedIntValue],enabling);
    } else {
        double anchorX=0,anchorY=0;
        if(partialLayout) {
            NSDictionary *anchor=nil;
            for(NSDictionary *d in saved) if(CGDisplayIsActive([d[@"id"] unsignedIntValue]) && [uuidFor([d[@"id"] unsignedIntValue]) isEqual:d[@"uuid"]]) {
                if(!anchor || [d[@"main"] boolValue] || (![anchor[@"main"] boolValue] && CGDisplayIsBuiltin([d[@"id"] unsignedIntValue]))) anchor=d;
            }
            if(anchor) { anchorX=[anchor[@"x"] doubleValue]; anchorY=[anchor[@"y"] doubleValue]; }
        }
        for(NSDictionary *d in saved) {
            CGDirectDisplayID display=[d[@"id"] unsignedIntValue];
            if(partialLayout && !CGDisplayIsActive(display)) continue;
            NSString *currentUUID=uuidFor(display);
            // A deliberately disabled display loses its CoreDisplay UUID. The fresh,
            // same-boot recovery lease retains the ID captured before disable.
            BOOL identityOK=canRestoreCachedDisplay([lease[@"boot"] isEqual:bootID()],[currentUUID isEqual:d[@"uuid"]],!currentUUID.length || [currentUUID isEqual:@"00000000-0000-0000-0000-000000000000"],CGDisplayIsOnline(display),CGDisplayIsActive(display));
            if(!identityOK) { CGCancelDisplayConfiguration(config); return failure(@"Identity changed during restore; refusing another display"); }
            if([d[@"active"] boolValue] && !CGDisplayIsActive(display)) { e=configure(config,display,true); if(e) break; }
            if(restoringOffline) continue; // Reconnect first; layout is a separate transaction after enumeration.
            e=CGConfigureDisplayOrigin(config,display,[d[@"x"] intValue]-(int)anchorX,[d[@"y"] intValue]-(int)anchorY); if(e) break;
            CFArrayRef modes=CGDisplayCopyAllDisplayModes(display,NULL);
            if(modes) {
                for(CFIndex i=0;i<CFArrayGetCount(modes);i++) {
                    CGDisplayModeRef mode=(CGDisplayModeRef)CFArrayGetValueAtIndex(modes,i);
                    if(CGDisplayModeGetIODisplayModeID(mode)==[d[@"mode"] unsignedIntValue]) { e=CGConfigureDisplayWithDisplayMode(config,display,mode,NULL); break; }
                }
                CFRelease(modes);
            }
            if(e) break;
        }
    }
    if(e) { CGCancelDisplayConfiguration(config); return failure([NSString stringWithFormat:@"Configure failed: %d",e]); }
    e=CGCompleteDisplayConfiguration(config,kCGConfigureForSession);
    if(e) return failure([NSString stringWithFormat:@"Commit failed: %d",e]);
    output(@{@"ok":@YES,@"displays":snapshot()}); return 0;
} }
