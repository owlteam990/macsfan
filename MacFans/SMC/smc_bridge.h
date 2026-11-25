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

/** SMC 协议成功 */
enum { kSMCResultSuccess = 0x00 };
/** 固件拒绝命令（常见于 Mode 3 下写模式键） */
enum { kSMCResultBadCommand = 0x82 };
/** 键不存在 */
enum { kSMCResultNotFound = 0x84 };
/** 键大小不匹配（部分机型写 Tg 仍可能生效） */
enum { kSMCResultKeySizeMismatch = 0x87 };

bool smc_open(io_connect_t *conn);
void smc_close(io_connect_t conn);

/**
 * 读取键信息。
 * @return 是否成功（IOKit 成功且 SMC result == 0）
 */
bool smc_get_key_info(io_connect_t conn, uint32_t key, uint32_t *size, uint32_t *type);

/**
 * 读取键值。
 * @return 是否成功（IOKit 成功且 SMC result == 0）
 */
bool smc_read_key(io_connect_t conn, uint32_t key, uint8_t *outBytes, uint32_t *inoutSize, uint32_t *outType);

/**
 * 写入键值。
 * @return 是否成功（IOKit 成功且 SMC result == 0 或可接受的 0x87）
 */
bool smc_write_key(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size);

/**
 * 写入键值并返回 SMC result 字节。
 * @param outResult 可选；IOKit 失败时为 0xFF
 * @return IOKit 调用是否成功（与 SMC result 无关）
 */
bool smc_write_key_ex(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size, uint8_t *outResult);

bool smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *outKey);
uint32_t smc_fourcc(const char *str);
size_t smc_keydata_size(void);

#ifdef __cplusplus
}
#endif
#endif
