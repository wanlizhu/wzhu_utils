// SPDX-License-Identifier: Apache-2.0

#include "wzhu_hooks.h"
#include "layer_core/wzhu_layer_dispatch.h"
#include <cstring>

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetInstanceProcAddr(
    VkInstance instance,
    const char* name
) {
    if (name == nullptr) {
        return nullptr;
    }

#define WZHU_RESOLVE_INSTANCE_SYMBOL(symbol_name, handler) \
    if (std::strcmp(name, symbol_name) == 0) { \
        return reinterpret_cast<PFN_vkVoidFunction>(handler); \
    }

    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateInstance", InterceptCreateInstance);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkDestroyInstance", InterceptDestroyInstance);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateDevice", InterceptCreateDevice);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkDestroyDevice", InterceptDestroyDevice);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetInstanceProcAddr", InterceptGetInstanceProcAddr);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetDeviceProcAddr", InterceptGetDeviceProcAddr);

    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
        InterceptGetPhysicalDeviceSurfaceCapabilitiesKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceFormatsKHR",
        InterceptGetPhysicalDeviceSurfaceFormatsKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfacePresentModesKHR",
        InterceptGetPhysicalDeviceSurfacePresentModesKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceSupportKHR",
        InterceptGetPhysicalDeviceSurfaceSupportKHR
    );

#if defined(VK_USE_PLATFORM_XCB_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateXcbSurfaceKHR", InterceptCreateXcbSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateXlibSurfaceKHR", InterceptCreateXlibSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateWaylandSurfaceKHR", InterceptCreateWaylandSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateWin32SurfaceKHR", InterceptCreateWin32SurfaceKHR);
#endif
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkCreateDisplayPlaneSurfaceKHR",
        InterceptCreateDisplayPlaneSurfaceKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceDisplayPropertiesKHR",
        InterceptGetPhysicalDeviceDisplayPropertiesKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceDisplayPlanePropertiesKHR",
        InterceptGetPhysicalDeviceDisplayPlanePropertiesKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetDisplayModePropertiesKHR", InterceptGetDisplayModePropertiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetDisplayPlaneSupportedDisplaysKHR",
        InterceptGetDisplayPlaneSupportedDisplaysKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetDisplayPlaneCapabilitiesKHR",
        InterceptGetDisplayPlaneCapabilitiesKHR
    );
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateDisplayModeKHR", InterceptCreateDisplayModeKHR);

#undef WZHU_RESOLVE_INSTANCE_SYMBOL

    WZHU_InstanceDispatchTable* dispatchTable = WZHU_instanceDispatchTableFor(instance);
    if (dispatchTable == nullptr || dispatchTable->pfn_getInstanceProcAddr == nullptr) {
        return nullptr;
    }
    return dispatchTable->pfn_getInstanceProcAddr(instance, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetDeviceProcAddr(
    VkDevice device,
    const char* name
) {
    if (name == nullptr) {
        return nullptr;
    }

#define WZHU_RESOLVE_DEVICE_SYMBOL(symbol_name, handler) \
    if (std::strcmp(name, symbol_name) == 0) { \
        return reinterpret_cast<PFN_vkVoidFunction>(handler); \
    }

    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceProcAddr", InterceptGetDeviceProcAddr);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkDestroyDevice", InterceptDestroyDevice);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceQueue", InterceptGetDeviceQueue);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceQueue2", InterceptGetDeviceQueue2);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkCreateSwapchainKHR", InterceptCreateSwapchainKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkDestroySwapchainKHR", InterceptDestroySwapchainKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetSwapchainImagesKHR", InterceptGetSwapchainImagesKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkAcquireNextImageKHR", InterceptAcquireNextImageKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkAcquireNextImage2KHR", InterceptAcquireNextImage2KHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueuePresentKHR", InterceptQueuePresentKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueSubmit", InterceptQueueSubmit);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueSubmit2", InterceptQueueSubmit2);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueBindSparse", InterceptQueueBindSparse);

#undef WZHU_RESOLVE_DEVICE_SYMBOL

    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_getDeviceProcAddr == nullptr) {
        return nullptr;
    }
    return dispatchTable->pfn_getDeviceProcAddr(device, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name
) {
    return InterceptGetInstanceProcAddr(instance, name);
}
