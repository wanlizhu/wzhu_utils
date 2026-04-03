// SPDX-License-Identifier: Apache-2.0
// Device / queue interceptors; dispatch/registry in layer_core/; timing report in utils/.

#include "wzhu_hooks.h"
#include "utils/wzhu_timing_statistics.h"
#include "layer_core/wzhu_layer_dispatch.h"
#include <chrono>

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* create_info,
    const VkAllocationCallbacks* allocator,
    VkSwapchainKHR* out_swapchain) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_createSwapchainKhr == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result = dispatchTable->pfn_createSwapchainKhr(
        device,
        create_info,
        allocator,
        out_swapchain);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::CreateSwapchainKHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroySwapchainKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    const VkAllocationCallbacks* allocator) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_destroySwapchainKhr == nullptr) {
        return;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    dispatchTable->pfn_destroySwapchainKhr(device, swapchain, allocator);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::DestroySwapchainKHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetSwapchainImagesKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint32_t* image_count,
    VkImage* images) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_getSwapchainImagesKhr == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result =
        dispatchTable->pfn_getSwapchainImagesKhr(device, swapchain, image_count, images);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::GetSwapchainImagesKHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImageKHR(
    VkDevice device,
    VkSwapchainKHR swapchain,
    uint64_t timeout_nanoseconds,
    VkSemaphore semaphore,
    VkFence fence,
    uint32_t* image_index) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_acquireNextImageKhr == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result = dispatchTable->pfn_acquireNextImageKhr(
        device,
        swapchain,
        timeout_nanoseconds,
        semaphore,
        fence,
        image_index);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::AcquireNextImageKHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkAcquireNextImage2KHR(
    VkDevice device,
    const VkAcquireNextImageInfoKHR* acquire_info,
    uint32_t* image_index) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_acquireNextImage2Khr == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result =
        dispatchTable->pfn_acquireNextImage2Khr(device, acquire_info, image_index);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::AcquireNextImage2KHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueuePresentKHR(
    VkQueue queue,
    const VkPresentInfoKHR* present_info) {
    const VkDevice device = WZHU_deviceHandleForQueue(queue);
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_queuePresentKhr == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result = dispatchTable->pfn_queuePresentKhr(queue, present_info);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::QueuePresentKHR,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    if (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR) {
        WZHU_recordPresent();
        WZHU_sampleGpuTimestamp(dispatchTable, device);
    }
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo* submits,
    VkFence fence) {
    const VkDevice device = WZHU_deviceHandleForQueue(queue);
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_queueSubmit == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result = dispatchTable->pfn_queueSubmit(queue, submit_count, submits, fence);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::QueueSubmit,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueSubmit2(
    VkQueue queue,
    uint32_t submit_count,
    const VkSubmitInfo2* submits,
    VkFence fence) {
    const VkDevice device = WZHU_deviceHandleForQueue(queue);
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_queueSubmit2 == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result = dispatchTable->pfn_queueSubmit2(queue, submit_count, submits, fence);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::QueueSubmit2,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkQueueBindSparse(
    VkQueue queue,
    uint32_t bind_info_count,
    const VkBindSparseInfo* bind_infos,
    VkFence fence) {
    const VkDevice device = WZHU_deviceHandleForQueue(queue);
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_queueBindSparse == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const auto timeStart = std::chrono::steady_clock::now();
    const VkResult result =
        dispatchTable->pfn_queueBindSparse(queue, bind_info_count, bind_infos, fence);
    const auto timeEnd = std::chrono::steady_clock::now();
    WZHU_recordVulkanAPINanoseconds(
        VulkanAPI_ID::QueueBindSparse,
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count());
    return result;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue(
    VkDevice device,
    uint32_t queue_family_index,
    uint32_t queue_index,
    VkQueue* out_queue) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_getDeviceQueue == nullptr) {
        return;
    }
    dispatchTable->pfn_getDeviceQueue(device, queue_family_index, queue_index, out_queue);
    if (out_queue != nullptr && *out_queue != VK_NULL_HANDLE) {
        WZHU_registerQueueHandle(*out_queue, device);
    }
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkGetDeviceQueue2(
    VkDevice device,
    const VkDeviceQueueInfo2* queue_info,
    VkQueue* out_queue) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_getDeviceQueue2 == nullptr) {
        return;
    }
    dispatchTable->pfn_getDeviceQueue2(device, queue_info, out_queue);
    if (out_queue != nullptr && *out_queue != VK_NULL_HANDLE) {
        WZHU_registerQueueHandle(*out_queue, device);
    }
}
