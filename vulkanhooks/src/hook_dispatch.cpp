// SPDX-License-Identifier: Apache-2.0

#include "wzhu_hooks.h"
#include "layer_core/wzhu_layer_dispatch.h"
#include <cstring>

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetInstanceProcAddr(
    VkInstance instance,
    const char* name) {
    if (name == nullptr) {
        return nullptr;
    }

#define WZHU_RESOLVE_INSTANCE_SYMBOL(symbol_name, handler)    \
    if (std::strcmp(name, symbol_name) == 0) {                \
        return reinterpret_cast<PFN_vkVoidFunction>(handler); \
    }

    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateInstance", IMPL_vkCreateInstance);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkDestroyInstance", IMPL_vkDestroyInstance);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateDevice", IMPL_vkCreateDevice);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkDestroyDevice", IMPL_vkDestroyDevice);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetInstanceProcAddr", IMPL_vkGetInstanceProcAddr);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetDeviceProcAddr", IMPL_vkGetDeviceProcAddr);

    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
        IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceFormatsKHR",
        IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfacePresentModesKHR",
        IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceSurfaceSupportKHR",
        IMPL_vkGetPhysicalDeviceSurfaceSupportKHR);

#if defined(VK_USE_PLATFORM_XCB_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateXcbSurfaceKHR", IMPL_vkCreateXcbSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateXlibSurfaceKHR", IMPL_vkCreateXlibSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateWaylandSurfaceKHR", IMPL_vkCreateWaylandSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateWin32SurfaceKHR", IMPL_vkCreateWin32SurfaceKHR);
#endif
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkCreateDisplayPlaneSurfaceKHR",
        IMPL_vkCreateDisplayPlaneSurfaceKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceDisplayPropertiesKHR",
        IMPL_vkGetPhysicalDeviceDisplayPropertiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetPhysicalDeviceDisplayPlanePropertiesKHR",
        IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkGetDisplayModePropertiesKHR", IMPL_vkGetDisplayModePropertiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetDisplayPlaneSupportedDisplaysKHR",
        IMPL_vkGetDisplayPlaneSupportedDisplaysKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL(
        "vkGetDisplayPlaneCapabilitiesKHR",
        IMPL_vkGetDisplayPlaneCapabilitiesKHR);
    WZHU_RESOLVE_INSTANCE_SYMBOL("vkCreateDisplayModeKHR", IMPL_vkCreateDisplayModeKHR);

#undef WZHU_RESOLVE_INSTANCE_SYMBOL

    WZHU_InstanceDispatchTable* dispatchTable = WZHU_instanceDispatchTableFor(instance);
    if (dispatchTable == nullptr || dispatchTable->pfn_getInstanceProcAddr == nullptr) {
        return nullptr;
    }
    return dispatchTable->pfn_getInstanceProcAddr(instance, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetDeviceProcAddr(
    VkDevice device,
    const char* name) {
    if (name == nullptr) {
        return nullptr;
    }

#define WZHU_RESOLVE_DEVICE_SYMBOL(symbol_name, handler)      \
    if (std::strcmp(name, symbol_name) == 0) {                \
        return reinterpret_cast<PFN_vkVoidFunction>(handler); \
    }

    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceProcAddr", IMPL_vkGetDeviceProcAddr);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkDestroyDevice", IMPL_vkDestroyDevice);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceQueue", IMPL_vkGetDeviceQueue);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetDeviceQueue2", IMPL_vkGetDeviceQueue2);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkCreateSwapchainKHR", IMPL_vkCreateSwapchainKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkDestroySwapchainKHR", IMPL_vkDestroySwapchainKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkGetSwapchainImagesKHR", IMPL_vkGetSwapchainImagesKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkAcquireNextImageKHR", IMPL_vkAcquireNextImageKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkAcquireNextImage2KHR", IMPL_vkAcquireNextImage2KHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueuePresentKHR", IMPL_vkQueuePresentKHR);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueSubmit", IMPL_vkQueueSubmit);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueSubmit2", IMPL_vkQueueSubmit2);
    WZHU_RESOLVE_DEVICE_SYMBOL("vkQueueBindSparse", IMPL_vkQueueBindSparse);

#undef WZHU_RESOLVE_DEVICE_SYMBOL

    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_getDeviceProcAddr == nullptr) {
        return nullptr;
    }
    return dispatchTable->pfn_getDeviceProcAddr(device, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name) {
    return IMPL_vkGetInstanceProcAddr(instance, name);
}
