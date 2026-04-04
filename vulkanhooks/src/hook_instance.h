#pragma once
#include "config.h"

PFN_vkGetInstanceProcAddr WZHU_getNextGIPA();

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateInstance(
    const VkInstanceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkInstance* outInstance
);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkEnumeratePhysicalDevices(
    VkInstance instance,
    uint32_t* physicalDeviceCount,
    VkPhysicalDevice* physicalDevices
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkDevice* outDevice
);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator
);

#ifdef HOOK_VULKAN_SURFACE_API
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    VkSurfaceCapabilitiesKHR* capabilities
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* formatCount,
    VkSurfaceFormatKHR* formats
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* modeCount,
    VkPresentModeKHR* modes
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceSupportKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t queueFamilyIndex,
    VkSurfaceKHR surface,
    VkBool32* supported
);

#if defined(VK_USE_PLATFORM_XCB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXcbSurfaceKHR(
    VkInstance instance,
    const VkXcbSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
);
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXlibSurfaceKHR(
    VkInstance instance,
    const VkXlibSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
);
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWaylandSurfaceKHR(
    VkInstance instance,
    const VkWaylandSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
);
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWin32SurfaceKHR(
    VkInstance instance,
    const VkWin32SurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
);
#endif

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayPlaneSurfaceKHR(
    VkInstance instance,
    const VkDisplaySurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPropertiesKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPlanePropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayModePropertiesKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    uint32_t* propertyCount,
    VkDisplayModePropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneSupportedDisplaysKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t planeIndex,
    uint32_t* displayCount,
    VkDisplayKHR* displays
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneCapabilitiesKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayModeKHR mode,
    uint32_t planeIndex,
    VkDisplayPlaneCapabilitiesKHR* capabilities
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayModeKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    const VkDisplayModeCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkDisplayModeKHR* outMode
);
#endif // HOOK_VULKAN_SURFACE_API