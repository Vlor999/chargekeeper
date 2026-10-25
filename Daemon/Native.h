// C API over AppleSMC and private PowerUI.framework (Manual Charge Limit).
#include <stdint.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

int smc_open(void);
int smc_has(const char *key);
int smc_read(const char *key, uint8_t *buf, uint32_t *len);  // buf: 32 bytes
int smc_write(const char *key, const uint8_t *buf, uint32_t len);

int mcl_available(void);
int mcl_enabled(void);
int mcl_limit(void);
int mcl_set(int limit);  // 100 disables MCL

// IOPMLibPrivate SPI, same effect as `pmset disablesleep`.
IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);
