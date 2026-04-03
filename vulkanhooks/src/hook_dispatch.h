#pragma once
#include "config.h"

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetInstanceProcAddr(
    VkInstance instance,
    const char* name
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetDeviceProcAddr(
    VkDevice device,
    const char* name
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name
);
