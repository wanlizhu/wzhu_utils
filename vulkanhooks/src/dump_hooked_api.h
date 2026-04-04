#pragma once
#include "config.h"
#include "layer_log.h"
#include "utils_device.h"

const char* WZHU_timestamp();

#ifdef DUMP_HOOKED_API
void WZHU_dump_vkCreateInstance(
    const VkInstanceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkInstance* outInstance,
    uint32_t microseconds
);

void WZHU_dump_vkCreateDevice(
    VkPhysicalDevice physicalDevice, 
    const VkDeviceCreateInfo* pCreateInfo, 
    const VkAllocationCallbacks* pAllocator, 
    VkDevice* pDevice,
    uint32_t microseconds
);
#else
#define WZHU_dump_vkCreateInstance(...) 
#define WZHU_dump_vkCreateDevice(...)
#endif 