#include <stdint.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

enum { kSMCBytesSize = 32 };
enum { kMCLReadFailed = -1, kMCLDisabledLimit = 100 };

int smc_open(void);
int smc_has(const char *key);
int smc_read(const char *key, uint8_t buf[kSMCBytesSize], uint32_t *len);
int smc_write(const char *key, const uint8_t *buf, uint32_t len);

int mcl_available(void);
int mcl_enabled(void);
int mcl_limit(void);
int mcl_set(int limit);

// exception: IOPMSetSystemPowerSetting is private IOKit SPI with no public header (https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLibPrivate.h)
IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);
