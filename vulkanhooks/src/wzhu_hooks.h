#pragma once

#include <vulkan/vulkan.h>

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSwapchainKHR* out_swapchain);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroySwapchainKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkAllocationCallbacks* allocator);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetSwapchainImagesKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint32_t* image_count,
    VkImage* images);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImageKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint64_t timeout_nanoseconds,
    VkSemaphore semaphore,
    VkFence fence,
    uint32_t* image_index);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImage2KHR(
    VkDevice device,
    const VkAcquireNextImageInfoKHR* acquire_info,
    uint32_t* image_index);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueuePresentKHR(
    VkQueue queue,
    const VkPresentInfoKHR* present_info);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo* submits,
    VkFence fence);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit2(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo2* submits,
    VkFence fence);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueBindSparse(
    VkQueue queue,
    uint32_t bind_info_count,
    const VkBindSparseInfo* bind_infos,
    VkFence fence);

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue(
    VkDevice device,
    uint32_t queue_family_index,
    uint32_t queue_index,
    VkQueue* out_queue);

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue2(
    VkDevice device,
    const VkDeviceQueueInfo2* queue_info,
    VkQueue* out_queue);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateInstance(
    const VkInstanceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkInstance* out_instance);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDevice(
    VkPhysicalDevice physical_device,
    const VkDeviceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkDevice* out_device);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetInstanceProcAddr(
    VkInstance instance,
    const char* name);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetDeviceProcAddr(
    VkDevice device,
    const char* name);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    VkSurfaceCapabilitiesKHR* capabilities);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    uint32_t* format_count,
    VkSurfaceFormatKHR* formats);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkSurfaceKHR surface,
    uint32_t* mode_count,
    VkPresentModeKHR* modes);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceSupportKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t queue_family_index,
    VkSurfaceKHR surface,
    VkBool32* supported);

#if defined(VK_USE_PLATFORM_XCB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXcbSurfaceKHR(
    VkInstance instance,
    const VkXcbSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface);
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXlibSurfaceKHR(
    VkInstance instance,
    const VkXlibSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface);
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWaylandSurfaceKHR(
    VkInstance instance,
    const VkWaylandSurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface);
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWin32SurfaceKHR(
    VkInstance instance,
    const VkWin32SurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface);
#endif

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayPlaneSurfaceKHR(
    VkInstance instance,
    const VkDisplaySurfaceCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* out_surface);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t* property_count,
    VkDisplayPropertiesKHR* properties);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t* property_count,
    VkDisplayPlanePropertiesKHR* properties);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayModePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayKHR display,
    uint32_t* property_count,
    VkDisplayModePropertiesKHR* properties);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneSupportedDisplaysKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    uint32_t plane_index,
    uint32_t* display_count,
    VkDisplayKHR* displays);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayModeKHR mode,
    uint32_t plane_index,
    VkDisplayPlaneCapabilitiesKHR* capabilities);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayModeKHR(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDisplayKHR display,
    const VkDisplayModeCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkDisplayModeKHR* out_mode);
