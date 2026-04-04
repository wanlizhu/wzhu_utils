#pragma once
#include "config.h"
#include <vulkan/vulkan_core.h>

const char* WZHU_driverVersion(
    uint32_t vendorID,
    uint32_t driverVersion
);

struct WZHU_GPUInfo {
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties props{};
    std::vector<VkQueueFamilyProperties> queueFamilies;

    WZHU_GPUInfo(VkPhysicalDevice gpu);
};