#pragma once
#include "config.h"
#include "layer_log.h"

const char* WZHU_timestamp();

#ifdef DUMP_HOOKED_API
void WZHU_dump_vkCreateInstance(
    const VkInstanceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkInstance* outInstance
);

void WZHU_dump_vkCreateDevice(
    VkPhysicalDevice physicalDevice, 
    const VkDeviceCreateInfo* pCreateInfo, 
    const VkAllocationCallbacks* pAllocator, 
    VkDevice* pDevice
);
#else
#define WZHU_dump_vkCreateInstance(...) 
#define WZHU_dump_vkCreateDevice(...)
#endif 