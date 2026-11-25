#include "smc_bridge.h"
#include <string.h>

uint32_t smc_fourcc(const char *str) {
    uint32_t result = 0;
    if (!str) return 0;
    for (int i = 0; i < 4 && str[i]; i++) {
        result |= ((uint32_t)(uint8_t)str[i]) << (8 * (3 - i));
    }
    return result;
}

bool smc_open(io_connect_t *conn) {
    if (!conn) return false;
    *conn = 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return false;
    kern_return_t kr = IOServiceOpen(service, mach_task_self_, 0, conn);
    IOObjectRelease(service);
    return kr == KERN_SUCCESS;
}

void smc_close(io_connect_t conn) {
    if (conn) IOServiceClose(conn);
}

static bool smc_call(io_connect_t conn, SMCKeyData *input, SMCKeyData *output) {
    size_t inSize = sizeof(SMCKeyData);
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCKernelIndex, input, inSize, output, &outSize);
    return kr == KERN_SUCCESS;
}

bool smc_get_key_info(io_connect_t conn, uint32_t key, uint32_t *size, uint32_t *type) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    if (!smc_call(conn, &input, &output)) return false;
    if (size) *size = output.keyInfo.dataSize;
    if (type) *type = output.keyInfo.dataType;
    return true;
}

bool smc_read_key(io_connect_t conn, uint32_t key, uint8_t *outBytes, uint32_t *inoutSize, uint32_t *outType) {
    uint32_t size = 0;
    uint32_t type = 0;
    if (!smc_get_key_info(conn, key, &size, &type)) return false;
    if (inoutSize && *inoutSize > 0 && *inoutSize < size) size = *inoutSize;

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = size;
    input.data8 = kSMCReadKey;

    if (!smc_call(conn, &input, &output)) return false;
    if (outBytes) memcpy(outBytes, output.bytes, size);
    if (inoutSize) *inoutSize = size;
    if (outType) *outType = type;
    return true;
}

bool smc_write_key(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size) {
    uint32_t infoSize = 0;
    if (!smc_get_key_info(conn, key, &infoSize, NULL)) return false;
    if (size > infoSize) size = infoSize;

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = size;
    input.data8 = kSMCWriteKey;
    if (bytes) memcpy(input.bytes, bytes, size);

    return smc_call(conn, &input, &output);
}

bool smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *outKey) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = kSMCGetKeyFromIndex;
    input.data32 = index;
    if (!smc_call(conn, &input, &output)) return false;
    if (outKey) *outKey = output.key;
    return true;
}
size_t smc_keydata_size(void) { return sizeof(SMCKeyData); }
