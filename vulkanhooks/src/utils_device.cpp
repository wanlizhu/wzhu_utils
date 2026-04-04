#include "utils_device.h"
#include "config.h"
#include <cstdio>
#include <cstring>
#include <vulkan/vulkan_core.h>

const char* WZHU_driverVersion(
    uint32_t vendorID,
    uint32_t driverVersion
) {
    static char szbuf[256];
    int major, minor, patch;
    
    if (vendorID == 0x10DE) {
        major = (driverVersion >> 22) & 0x3FFu;
        minor = (driverVersion >> 14) & 0xFFu;
        patch = (driverVersion >> 6) & 0xFFu;
    } else {
        major = VK_VERSION_MAJOR(driverVersion);
        minor = VK_VERSION_MINOR(driverVersion);
        patch = VK_VERSION_PATCH(driverVersion);
    }

    memset(szbuf, 0, sizeof(szbuf));
    snprintf(szbuf, sizeof(szbuf), "%d.%d.%d", major, minor, patch);
    return szbuf;
}

WZHU_GPUInfo::WZHU_GPUInfo(VkPhysicalDevice gpu)
    : physicalDevice(gpu) {
    if (gpu == VK_NULL_HANDLE) {
        return;
    }

    INSTANCE_FUNC(vkGetPhysicalDeviceProperties)(physicalDevice, &props);

    uint32_t familiesCount = 0;
    INSTANCE_FUNC(vkGetPhysicalDeviceQueueFamilyProperties)(physicalDevice, &familiesCount, NULL);
    queueFamilies.resize(familiesCount);
    INSTANCE_FUNC(vkGetPhysicalDeviceQueueFamilyProperties)(physicalDevice, &familiesCount, queueFamilies.data());
    
    
}