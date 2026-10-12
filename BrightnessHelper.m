// Brightness-only helper. Transport derived from MIT-licensed waydabber/m1ddc.
@import Foundation;
@import IOKit;
#include "ThirdParty/m1ddc/headers/ioregistry.h"
#include "ThirdParty/m1ddc/headers/i2c.h"
#include "BrightnessProtocol.h"
#include <errno.h>
static int output(NSDictionary *result, int code) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); return code;
}
static BOOL readValue(DDCTransport transport, uint16_t *current, uint16_t *maximum) {
    for (int attempt = 0; attempt < 3; attempt++) {
        DDCPacket request = createDDCPacket(LUMINANCE);
        prepareDDCRead(request.data);
        if (performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &request)) continue;
        usleep(50000);
        DDCPacket reply = {}; reply.inputAddr = DEFAULT_INPUT_ADDRESS;
        if (!performDDCReadAtChipAddress(transport.service, transport.chipAddress, &reply) &&
            RetinaDecodeBrightness(reply.data, 12, current, maximum)) return YES;
    }
    return NO;
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc < 4 || (strcmp(argv[1], "--probe") && strcmp(argv[1], "--set"))) return output(@{@"error":@"参数无效"}, 1);
    char *end = NULL; errno = 0; unsigned long id = strtoul(argv[2], &end, 10);
    if (errno || !*argv[2] || *end || id > UINT32_MAX || !CGDisplayIsOnline((CGDirectDisplayID)id) || CGDisplayIsBuiltin((CGDirectDisplayID)id) || CGDisplayVendorNumber((CGDirectDisplayID)id) == 0xB33F)
        return output(@{@"error":@"目标不是已连接的实体外接显示器"}, 1);
    BOOL writing = !strcmp(argv[1], "--set");
    double percent = 0;
    if (writing) {
        if (argc != 5) return output(@{@"error":@"缺少亮度值"}, 1);
        percent = strtod(argv[4], &end);
        if (!*argv[4] || *end || !isfinite(percent) || percent < 0 || percent > 100) return output(@{@"error":@"亮度必须为 0–100"}, 1);
    }
    DisplayInfos displays[MAX_DISPLAYS] = {};
    CGDisplayCount count = getOnlineDisplayInfos(displays);
    DisplayInfos *selected = NULL;
    for (CGDisplayCount i = 0; i < count; i++) if (displays[i].id == id) selected = &displays[i];
    if (!selected) return output(@{@"error":@"无法找到显示器硬件通道；请检查连接方式"}, 1);
    if ([selected->uuid caseInsensitiveCompare:@(argv[3])] != NSOrderedSame) return output(@{@"error":@"显示器连接已变化，请重新打开亮度窗口"}, 1);
    DDCTransport transport = getDisplayDDCTransport(selected);
    if (!transport.service) return output(@{@"error":@"此连接没有可用的 DDC/CI 硬件通道"}, 1);
    uint16_t current = 0, maximum = 0;
    if (!readValue(transport, &current, &maximum)) return output(@{@"error":@"显示器未响应亮度读取；请在显示器菜单启用 DDC/CI，并检查线缆或转接器"}, 1);
    if (writing) {
        uint16_t target = RetinaBrightnessValue(percent, maximum);
        DDCPacket packet = createDDCPacket(LUMINANCE); prepareDDCWrite(&packet, target);
        if (performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &packet)) return output(@{@"error":@"显示器拒绝亮度写入"}, 1);
        usleep(150000);
        if (!readValue(transport, &current, &maximum) || abs((int)current - (int)target) > MAX(1, maximum / 100)) return output(@{@"error":@"亮度写入未能读回确认；请重新读取当前亮度"}, 1);
    }
    CFRelease(transport.service);
    return output(@{@"displayID":@(id), @"current":@(current), @"maximum":@(maximum), @"percent":@(100.0 * current / maximum)}, 0);
} }
