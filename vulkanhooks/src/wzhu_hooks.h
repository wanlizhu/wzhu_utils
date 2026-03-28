#pragma once

#include <vulkan/vulkan.h>

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSwapchainKHR* out_swapchain
);

VKAPI_ATTR void VKAPI_CALL InterceptDestroySwapchainKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkAllocationCallbacks* allocator
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetSwapchainImagesKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint32_t* image_count,
    VkImage* images
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptAcquireNextImageKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint64_t timeout_nanoseconds,
    VkSemaphore semaphore,
    VkFence fence,
    uint32_t* image_index
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptAcquireNextImage2KHR(
    VkDevice device,
    const VkAcquireNextImageInfoKHR* acquire_info,
    uint32_t* image_index
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueuePresentKHR(
    VkQueue queue,
    const VkPresentInfoKHR* present_info
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueSubmit(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo* submits,
    VkFence fence
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueSubmit2(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo2* submits,
    VkFence fence
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueBindSparse(
    VkQueue queue,
    uint32_t bind_info_count,
    const VkBindSparseInfo* bind_infos,
    VkFence fence
);

VKAPI_ATTR void VKAPI_CALL InterceptGetDeviceQueue(
    VkDevice device,
    uint32_t queue_family_index,
    uint32_t queue_index,
    VkQueue* out_queue
);

VKAPI_ATTR void VKAPI_CALL InterceptGetDeviceQueue2(
    VkDevice device,
    const VkDeviceQueueInfo2* queue_info,
    VkQueue* out_queue
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateInstance(
    const VkInstanceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkInstance* out_instance
);

VKAPI_ATTR void VKAPI_CALL InterceptDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateDevice(
    VkPhysicalDevice physical_device,
    const VkDeviceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkDevice* out_device
);

VKAPI_ATTR void VKAPI_CALL InterceptDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetInstanceProcAddr(
    VkInstance instance,
    const char* name
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetDeviceProcAddr(
    VkDevice device,
    const char* name
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    VkSurfaceCapabilitiesKHR* capabilities
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceSurfaceFormatsKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    uint32_t* format_count,
    VkSurfaceFormatKHR* formats
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceSurfacePresentModesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    uint32_t* mode_count,
    VkPresentModeKHR* modes
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceSurfaceSupportKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t queue_family_index,
    VkSurfaceKHR surface,
    VkBool32* supported
);

#if defined(VK_USE_PLATFORM_XCB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateXcbSurfaceKHR(
    VkInstance instance,
    const VkXcbSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface
);
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateXlibSurfaceKHR(
    VkInstance instance,
    const VkXlibSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface
);
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateWaylandSurfaceKHR(
    VkInstance instance,
    const VkWaylandSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface
);
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateWin32SurfaceKHR(
    VkInstance instance,
    const VkWin32SurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface
);
#endif

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateDisplayPlaneSurfaceKHR(
    VkInstance instance,
    const VkDisplaySurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceDisplayPropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t* property_count,
    VkDisplayPropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetPhysicalDeviceDisplayPlanePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t* property_count,
    VkDisplayPlanePropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetDisplayModePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayKHR display,
    uint32_t* property_count,
    VkDisplayModePropertiesKHR* properties
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetDisplayPlaneSupportedDisplaysKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t plane_index,
    uint32_t* display_count,
    VkDisplayKHR* displays
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetDisplayPlaneCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayModeKHR mode,
    uint32_t plane_index,
    VkDisplayPlaneCapabilitiesKHR* capabilities
);

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateDisplayModeKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayKHR display,
    const VkDisplayModeCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkDisplayModeKHR* out_mode
);
