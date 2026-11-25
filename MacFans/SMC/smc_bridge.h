#ifndef SMC_BRIDGE_H
#define SMC_BRIDGE_H

#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved[1];
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

enum { kSMCKernelIndex = 2 };

enum {
    kSMCReadKey         = 5,
    kSMCWriteKey        = 6,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo      = 9
};

bool smc_open(io_connect_t *conn);
void smc_close(io_connect_t conn);
bool smc_get_key_info(io_connect_t conn, uint32_t key, uint32_t *size, uint32_t *type);
bool smc_read_key(io_connect_t conn, uint32_t key, uint8_t *outBytes, uint32_t *inoutSize, uint32_t *outType);
bool smc_write_key(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size);
bool smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *outKey);
uint32_t smc_fourcc(const char *str);
size_t smc_keydata_size(void);

#ifdef __cplusplus
}
#endif
#endif
