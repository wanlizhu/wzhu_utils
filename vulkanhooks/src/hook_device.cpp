#include "hook_device.h"

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueuePresentKHR(
    VkQueue queue,
    const VkPresentInfoKHR* presentInfo
) {
    const auto queueDeviceIt = g_queueDeviceMap.find(queue);
    if (queueDeviceIt == g_queueDeviceMap.end()) {
        return VK_ERROR_UNKNOWN;
    }
    
    return GET_DEVICE_DISPATCH_TABLE(queueDeviceIt->second, vkQueuePresentKHR)->pfn_vkQueuePresentKHR(queue, presentInfo);
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit(
    VkQueue queue,
    uint32_t submitCount,
    const VkSubmitInfo* submits,
    VkFence fence
) {
    const auto queueDeviceIt = g_queueDeviceMap.find(queue);
    if (queueDeviceIt == g_queueDeviceMap.end()) {
        return VK_ERROR_UNKNOWN;
    }

    return GET_DEVICE_DISPATCH_TABLE(queueDeviceIt->second, vkQueueSubmit)->pfn_vkQueueSubmit(queue, submitCount, submits, fence);
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit2(
    VkQueue queue,
    uint32_t submitCount,
    const VkSubmitInfo2* submits,
    VkFence fence
) {
    const auto queueDeviceIt = g_queueDeviceMap.find(queue);
    if (queueDeviceIt == g_queueDeviceMap.end()) {
        return VK_ERROR_UNKNOWN;
    }

    return GET_DEVICE_DISPATCH_TABLE(queueDeviceIt->second, vkQueueSubmit2)->pfn_vkQueueSubmit2(queue, submitCount, submits, fence);
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueBindSparse(
    VkQueue queue,
    uint32_t bindInfoCount,
    const VkBindSparseInfo* bindInfos,
    VkFence fence
) {
    const auto queueDeviceIt = g_queueDeviceMap.find(queue);
    if (queueDeviceIt == g_queueDeviceMap.end()) {
        return VK_ERROR_UNKNOWN;
    }

    return GET_DEVICE_DISPATCH_TABLE(queueDeviceIt->second, vkQueueBindSparse)->pfn_vkQueueBindSparse(queue, bindInfoCount, bindInfos, fence);
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue(
    VkDevice device,
    uint32_t queueFamilyIndex,
    uint32_t queueIndex,
    VkQueue* outQueue
) {
    GET_DEVICE_DISPATCH_TABLE(device, vkGetDeviceQueue)->pfn_vkGetDeviceQueue(device, queueFamilyIndex, queueIndex, outQueue);

    if (outQueue != nullptr && *outQueue != VK_NULL_HANDLE) {
        g_queueDeviceMap[*outQueue] = device;
    }
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue2(
    VkDevice device,
    const VkDeviceQueueInfo2* queueInfo,
    VkQueue* outQueue
) {
    GET_DEVICE_DISPATCH_TABLE(device, vkGetDeviceQueue2)->pfn_vkGetDeviceQueue2(device, queueInfo, outQueue);

    if (outQueue != nullptr && *outQueue != VK_NULL_HANDLE) {
        g_queueDeviceMap[*outQueue] = device;
    }
}

#ifdef HOOK_VULKAN_SWAPCHAIN_API
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSwapchainKHR* outSwapchain
) {
    return GET_DEVICE_DISPATCH_TABLE(device, vkCreateSwapchainKHR)->pfn_vkCreateSwapchainKHR(
        device,
        createInfo,
        allocator,
        outSwapchain
    );
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroySwapchainKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkAllocationCallbacks* allocator
) {
    GET_DEVICE_DISPATCH_TABLE(device, vkDestroySwapchainKHR)->pfn_vkDestroySwapchainKHR(device, swapchain, allocator);
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetSwapchainImagesKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint32_t* imageCount,
    VkImage* images
) {
    return GET_DEVICE_DISPATCH_TABLE(device, vkGetSwapchainImagesKHR)->pfn_vkGetSwapchainImagesKHR(
        device,
        swapchain,
        imageCount,
        images
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImageKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint64_t timeoutNanoseconds,
    VkSemaphore semaphore,
    VkFence fence,
    uint32_t* imageIndex
) {
    return GET_DEVICE_DISPATCH_TABLE(device, vkAcquireNextImageKHR)->pfn_vkAcquireNextImageKHR(
        device,
        swapchain,
        timeoutNanoseconds,
        semaphore,
        fence,
        imageIndex
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImage2KHR(
    VkDevice device,
    const VkAcquireNextImageInfoKHR* acquireInfo,
    uint32_t* imageIndex
) {
    return GET_DEVICE_DISPATCH_TABLE(device, vkAcquireNextImage2KHR)->pfn_vkAcquireNextImage2KHR(
        device,
        acquireInfo,
        imageIndex
    );
}
#endif // HOOK_VULKAN_SWAPCHAIN_API
