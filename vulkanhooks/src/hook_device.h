#pragma once
#include "config.h"

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueuePresentKHR(
    VkQueue queue,
    const VkPresentInfoKHR* presentInfo
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit(
    VkQueue queue,
    uint32_t submitCount,
    const VkSubmitInfo* submits,
    VkFence fence
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit2(
    VkQueue queue,
    uint32_t submitCount,
    const VkSubmitInfo2* submits,
    VkFence fence
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueBindSparse(
    VkQueue queue,
    uint32_t bindInfoCount,
    const VkBindSparseInfo* bindInfos,
    VkFence fence
);

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue(
    VkDevice device,
    uint32_t queueFamilyIndex,
    uint32_t queueIndex,
    VkQueue* outQueue
);

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue2(
    VkDevice device,
    const VkDeviceQueueInfo2* queueInfo,
    VkQueue* outQueue
);

#ifdef HOOK_VULKAN_SWAPCHAIN_API
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSwapchainKHR* outSwapchain
);

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroySwapchainKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkAllocationCallbacks* allocator
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetSwapchainImagesKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint32_t* imageCount,
    VkImage* images
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImageKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint64_t timeoutNanoseconds,
    VkSemaphore semaphore,
    VkFence fence,
    uint32_t* imageIndex
);

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImage2KHR(
    VkDevice device,
    const VkAcquireNextImageInfoKHR* acquireInfo,
    uint32_t* imageIndex
);
#endif // HOOK_VULKAN_SWAPCHAIN_API