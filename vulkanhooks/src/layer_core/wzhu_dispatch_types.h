#pragma once

#include <vulkan/vulkan.h>

struct WZHU_InstanceDispatchTable {
    PFN_vkGetInstanceProcAddr pfn_getInstanceProcAddr{};
    PFN_vkDestroyInstance pfn_destroyInstance{};
    PFN_vkCreateDevice pfn_createDevice{};
};

struct WZHU_DeviceDispatchTable {
    PFN_vkGetDeviceProcAddr pfn_getDeviceProcAddr{};
    PFN_vkDestroyDevice pfn_destroyDevice{};
    PFN_vkGetDeviceQueue pfn_getDeviceQueue{};
    PFN_vkGetDeviceQueue2 pfn_getDeviceQueue2{};
    PFN_vkCreateSwapchainKHR pfn_createSwapchainKhr{};
    PFN_vkDestroySwapchainKHR pfn_destroySwapchainKhr{};
    PFN_vkGetSwapchainImagesKHR pfn_getSwapchainImagesKhr{};
    PFN_vkAcquireNextImageKHR pfn_acquireNextImageKhr{};
    PFN_vkAcquireNextImage2KHR pfn_acquireNextImage2Khr{};
    PFN_vkQueuePresentKHR pfn_queuePresentKhr{};
    PFN_vkQueueSubmit pfn_queueSubmit{};
    PFN_vkQueueSubmit2 pfn_queueSubmit2{};
    PFN_vkQueueBindSparse pfn_queueBindSparse{};
    PFN_vkGetCalibratedTimestampsKHR pfn_getCalibratedTimestampsKhr{};

    VkDevice device{};
    VkPhysicalDevice physicalDevice{};
    bool hasCalibratedTimestamps{false};
};

struct WZHU_InstanceExtrasTable {
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR pfn_getSurfaceCaps{};
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR pfn_getSurfaceFormats{};
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR pfn_getSurfacePresentModes{};
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR pfn_getSurfaceSupport{};
#if defined(VK_USE_PLATFORM_XCB_KHR)
    PFN_vkCreateXcbSurfaceKHR pfn_createXcbSurface{};
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    PFN_vkCreateXlibSurfaceKHR pfn_createXlibSurface{};
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    PFN_vkCreateWaylandSurfaceKHR pfn_createWaylandSurface{};
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    PFN_vkCreateWin32SurfaceKHR pfn_createWin32Surface{};
#endif
    PFN_vkCreateDisplayPlaneSurfaceKHR pfn_createDisplayPlaneSurface{};
    PFN_vkGetPhysicalDeviceDisplayPropertiesKHR pfn_getDisplayProps{};
    PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR pfn_getDisplayPlaneProps{};
    PFN_vkGetDisplayModePropertiesKHR pfn_getDisplayModeProps{};
    PFN_vkGetDisplayPlaneSupportedDisplaysKHR pfn_getDisplayPlaneSupportedDisplays{};
    PFN_vkGetDisplayPlaneCapabilitiesKHR pfn_getDisplayPlaneCaps{};
    PFN_vkCreateDisplayModeKHR pfn_createDisplayMode{};
};
