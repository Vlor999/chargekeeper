#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include "Native.h"

typedef struct { char major, minor, build, reserved; UInt16 release; } SMCVers;
typedef struct { UInt16 version, length; UInt32 cpu, gpu, mem; } SMCPLimit;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVers vers;
    SMCPLimit pLimit;
    SMCKeyInfo keyInfo;
    char result, status, data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCParam;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyInfo = 9 };

static io_connect_t conn;

static UInt32 k4(const char *s) { return (UInt32)s[0] << 24 | (UInt32)s[1] << 16 | (UInt32)s[2] << 8 | (UInt32)s[3]; }

int smc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : -1;
}

static int smc_call(SMCParam *in, SMCParam *out) {
    size_t sz = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(SMCParam), out, &sz);
    return kr == KERN_SUCCESS && out->result == 0 ? 0 : -1;
}

static int smc_info(const char *key, SMCKeyInfo *info) {
    SMCParam in = {0}, out = {0};
    in.key = k4(key);
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &out)) return -1;
    *info = out.keyInfo;
    return 0;
}

int smc_has(const char *key) { SMCKeyInfo i; return smc_info(key, &i) == 0; }

int smc_read(const char *key, uint8_t *buf, uint32_t *len) {
    SMCKeyInfo info;
    if (smc_info(key, &info)) return -1;
    SMCParam in = {0}, out = {0};
    in.key = k4(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = kSMCReadKey;
    if (smc_call(&in, &out)) return -1;
    *len = info.dataSize;
    memcpy(buf, out.bytes, info.dataSize);
    return 0;
}

int smc_write(const char *key, const uint8_t *buf, uint32_t len) {
    SMCKeyInfo info;
    if (smc_info(key, &info) || info.dataSize != len) return -1;
    SMCParam in = {0}, out = {0};
    in.key = k4(key);
    in.keyInfo.dataSize = len;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, buf, len);
    return smc_call(&in, &out);
}

@interface PowerUISmartChargeClient : NSObject
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)e;
- (unsigned char)getMCLLimitWithError:(NSError **)e;
- (BOOL)enableMCL:(NSError **)e;
- (BOOL)disableMCL:(NSError **)e;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)e;
@end

static PowerUISmartChargeClient *client(void) {
    static PowerUISmartChargeClient *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW)) return;
        PowerUISmartChargeClient *x = [[NSClassFromString(@"PowerUISmartChargeClient") alloc] initWithClientName:@"jauge"];
        if ([x respondsToSelector:@selector(setMCLLimit:error:)] && [x isMCLSupported]) c = x;
    });
    return c;
}

int mcl_available(void) { return client() != nil; }
int mcl_enabled(void) { return client() ? (int)[client() isMCLCurrentlyEnabled:NULL] : 0; }
int mcl_limit(void) { return client() ? [client() getMCLLimitWithError:NULL] : 100; }

int mcl_set(int limit) {
    PowerUISmartChargeClient *c = client();
    if (!c) return -1;
    NSError *e = nil;
    BOOL ok = limit >= 100 ? [c setMCLLimit:100 error:&e] && [c disableMCL:&e]
                           : ([c isMCLCurrentlyEnabled:&e] || [c enableMCL:&e]) && [c setMCLLimit:limit error:&e];
    if (!ok) NSLog(@"MCL %d failed: %@", limit, e);
    return ok ? 0 : -1;
}
