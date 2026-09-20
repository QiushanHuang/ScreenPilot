@import Foundation;
@import IOKit;
@import CoreGraphics;
#include <dlfcn.h>
#include "ioregistry.h"
#include "DDCProtocol.h"
#include "ControlSafety.h"

extern IOReturn IOAVServiceReadI2C(IOAVServiceRef,uint32_t,uint32_t,void*,uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef,uint32_t,uint32_t,void*,uint32_t);
static void output(id value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes,1,data.length,stdout); puts("");
}
static int fail(NSString *message) { output(@{@"ok":@NO,@"error":message}); return 1; }
static NSDictionary *readVCP(DDCTransport t, uint8_t code) {
    uint8_t request[]={0x82,0x01,code,(uint8_t)(0x6e^0x82^0x01^code)};
    usleep(10000);
    IOReturn e=IOAVServiceWriteI2C(t.service,t.chipAddress,0x51,request,sizeof(request));
    if(!e) { usleep(10000); e=IOAVServiceWriteI2C(t.service,t.chipAddress,0x51,request,sizeof(request)); }
    if(e) return @{@"ok":@NO,@"error":@"DDC 读取请求失败"};
    usleep(60000);
    uint8_t reply[11]={0}; e=IOAVServiceReadI2C(t.service,t.chipAddress,0,reply,sizeof(reply));
    if(getenv("SCREENPILOT_DDC_TRACE")) { fprintf(stderr,"chip=%02x code=%02x result=%08x bytes=",t.chipAddress,code,e); for(int i=0;i<11;i++) fprintf(stderr,"%02x ",reply[i]); fprintf(stderr,"\n"); }
    if(e || !validVCPReply(reply,sizeof(reply),code))
        return @{@"ok":@NO,@"error":@"没有有效 DDC 回执（可能不支持或 DDC/CI 未开启）"};
    return @{@"ok":@YES,@"current":@((reply[8]<<8)|reply[9]),@"maximum":@((reply[6]<<8)|reply[7])};
}
static bool writeVCP(DDCTransport t,uint8_t code,uint16_t value) {
    uint8_t b[]={0x84,0x03,code,(uint8_t)(value>>8),(uint8_t)value,0};
    b[5]=0x6e^0x51^b[0]^b[1]^b[2]^b[3]^b[4];
    return IOAVServiceWriteI2C(t.service,t.chipAddress,0x51,b,sizeof(b))==kIOReturnSuccess;
}
static NSDictionary *identity(DisplayInfos d) {
    return @{@"id":@(d.id),@"uuid":d.uuid?:@"",@"location":d.ioLocation?:@"",
      @"name":d.productName?:@"Display",@"builtIn":@(CGDisplayIsBuiltin(d.id)),
      @"serial":@(d.serial),@"vendor":@(d.vendor),@"model":@(d.model)};
}
static bool number(const char *text,unsigned long *out) {
    if(!text || !*text || *text=='-') return false;
    char *end=NULL; *out=strtoul(text,&end,10); return end && !*end;
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    if(argc<2) return fail(@"Missing command");
    // One process per operation isolates private API failure and gives the parent a hard timeout.
    DisplayInfos displays[MAX_DISPLAYS]={0}; unsigned count=getOnlineDisplayInfos(displays);
    NSString *command=@(argv[1]);
    if([command isEqual:@"list"]) {
        NSMutableArray *list=[NSMutableArray array];
        for(unsigned i=0;i<count;i++) [list addObject:identity(displays[i])];
        output(@{@"ok":@YES,@"displays":list}); return 0;
    }
    if(argc<5) return fail(@"Missing exact device identity");
    unsigned long id=0; if(!number(argv[2],&id) || id>UINT32_MAX) return fail(@"Invalid display ID");
    NSString *uuid=@(argv[3]), *location=@(argv[4]);
    DisplayInfos *selected=NULL; int ids=0,uuids=0,locations=0;
    for(unsigned i=0;i<count;i++) {
        DisplayInfos *d=&displays[i];
        if(d->id==id) ids++;
        if([d->uuid isEqual:uuid]) uuids++;
        if([d->ioLocation isEqual:location]) locations++;
        if(d->id==id && [d->uuid isEqual:uuid] && [d->ioLocation isEqual:location]) selected=d;
    }
    if(!selected || ids!=1 || uuids!=1 || locations!=1 || !uuid.length || !location.length)
        return fail(@"显示器已改变或标识不唯一，请刷新后重试");
    if(CGDisplayIsBuiltin(selected->id)) {
        void *lib=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY);
        typedef int (*GetBrightness)(CGDirectDisplayID,float*);
        typedef int (*SetBrightness)(CGDirectDisplayID,float);
        GetBrightness get=lib?(GetBrightness)dlsym(lib,"DisplayServicesGetBrightness"):NULL;
        SetBrightness set=lib?(SetBrightness)dlsym(lib,"DisplayServicesSetBrightness"):NULL;
        if(!get || !set) return fail(@"系统原生亮度接口不可用");
        float value=0; if(get(selected->id,&value)) return fail(@"无法读取内置屏亮度");
        if([command isEqual:@"probe"] || [command isEqual:@"get"]) {
            output(@{@"ok":@YES,@"brightness":@{@"ok":@YES,@"current":@(lroundf(value*1000)),@"maximum":@1000},@"native":@YES}); return 0;
        }
        unsigned long raw=0;
        if(![command isEqual:@"set"] || argc!=7 || strcmp(argv[5],"brightness") || !number(argv[6],&raw) || raw>1000)
            return fail(@"内置屏仅支持亮度控制");
        if(set(selected->id,(float)raw/1000)) return fail(@"原生亮度设置失败");
        usleep(80000); if(get(selected->id,&value)) return fail(@"命令已发送，但无法读回亮度");
        output(@{@"ok":@YES,@"current":@(lroundf(value*1000)),@"maximum":@1000,@"verified":(abs((int)lroundf(value*1000)-(int)raw)<=10 ? @YES : @NO)}); return 0;
    }
    DDCTransport t=getDisplayDDCTransport(selected);
    if(!t.service) return fail(@"当前连接没有可用 DDC 通道");
    if([command isEqual:@"probe"]) {
        NSDictionary *brightness=readVCP(t,0x10); usleep(80000);
        NSDictionary *input=readVCP(t,0x60); usleep(80000);
        NSDictionary *power=powerControlBlocked(selected->vendor,selected->model) ? @{ @"ok":@NO,@"error":@"此型号电源控制曾造成雪花屏，已禁用" } : readVCP(t,0xd6);
        output(@{@"ok":@YES,@"brightness":brightness,@"input":input,@"power":power,@"native":@NO}); return 0;
    }
    if(argc<6) return fail(@"Missing feature");
    NSString *feature=@(argv[5]);
    uint8_t code=[feature isEqual:@"brightness"]?0x10:[feature isEqual:@"input"]?0x60:[feature isEqual:@"power"]?0xd6:0;
    if(!code) return fail(@"Unknown feature");
    if(code==0xd6 && powerControlBlocked(selected->vendor,selected->model)) return fail(@"此型号电源控制曾造成雪花屏，已禁用");
    if([command isEqual:@"get"]) { output(readVCP(t,code)); return 0; }
    unsigned long raw=0;
    if(![command isEqual:@"set"] || argc!=7 || !number(argv[6],&raw) || raw>65535) return fail(@"Invalid value");
    if(code==0x60 && raw!=15 && raw!=16 && raw!=17 && raw!=18 && raw!=27) return fail(@"Unsupported input value");
    if(code==0xd6 && raw!=1 && raw!=4) return fail(@"Unsupported power value");
    // Revalidate brightness range against this exact current display before writing.
    if(code==0x10) {
        NSDictionary *before=readVCP(t,code);
        if(![before[@"ok"] boolValue] || [before[@"maximum"] intValue]<=0 || raw>[before[@"maximum"] unsignedIntValue])
            return fail(@"无法验证显示器亮度范围");
    }
    if(!writeVCP(t,code,(uint16_t)raw)) return fail(@"DDC 写入失败");
    if(code!=0x10) {
        output(@{@"ok":@YES,@"verified":@NO,@"message":@"命令已发送；切换或休眠结果请观察屏幕确认"}); return 0;
    }
    usleep(120000); NSDictionary *after=readVCP(t,code);
    if(![after[@"ok"] boolValue]) return fail(@"命令已发送，但无法读回亮度");
    NSMutableDictionary *result=[after mutableCopy]; result[@"verified"]=([after[@"current"] intValue]==raw ? @YES : @NO);
    output(result); return 0;
} }
