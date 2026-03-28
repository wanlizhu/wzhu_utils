#pragma once
// Per-API CPU timing aggregates, optional GPU timestamp sampling (calibrated timestamps at present),
// present-based FPS counters, and the periodic stderr report thread.
// VulkanAPI_ID keys per-intercepted-call timing buckets for the report.

#include "layer_core/wzhu_dispatch_types.h"
#include <cstdint>

constexpr uint32_t kVulkanAPI_ID_BucketCount = 32;
constexpr double kVulkanAPI_ReportIntervalSeconds = 2.0;

enum class VulkanAPI_ID : uint32_t {
    CreateSwapchainKHR = 0,
    DestroySwapchainKHR,
    AcquireNextImageKHR,
    AcquireNextImage2KHR,
    QueuePresentKHR,
    QueueSubmit,
    QueueSubmit2,
    QueueBindSparse,
    GetSwapchainImagesKHR,
    GetPhysicalDeviceSurfaceCapabilitiesKHR,
    GetPhysicalDeviceSurfaceFormatsKHR,
    GetPhysicalDeviceSurfacePresentModesKHR,
    GetPhysicalDeviceSurfaceSupportKHR,
    CreateXcbSurfaceKHR,
    CreateXlibSurfaceKHR,
    CreateWaylandSurfaceKHR,
    CreateWin32SurfaceKHR,
    CreateDisplayPlaneSurfaceKHR,
    GetPhysicalDeviceDisplayPropertiesKHR,
    GetPhysicalDeviceDisplayPlanePropertiesKHR,
    GetDisplayModePropertiesKHR,
    GetDisplayPlaneSupportedDisplaysKHR,
    GetDisplayPlaneCapabilitiesKHR,
    CreateDisplayModeKHR,
    Count
};

static_assert(
    static_cast<uint32_t>(VulkanAPI_ID::Count) <= kVulkanAPI_ID_BucketCount,
    "vulkan api id table"
);

void WZHU_startReportThreadOnce();
void WZHU_recordVulkanAPINanoseconds(VulkanAPI_ID api_id, uint64_t elapsed_nanoseconds);
const char* WZHU_getVulkanAPIName(VulkanAPI_ID api_id);
void WZHU_sampleGpuTimestamp(WZHU_DeviceDispatchTable* dispatch, VkDevice device);
void WZHU_recordPresent();
uint32_t WZHU_getGpuTimestampStride();
