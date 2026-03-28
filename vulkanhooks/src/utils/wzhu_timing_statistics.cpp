// SPDX-License-Identifier: Apache-2.0
// Implementation: utils/wzhu_timing_statistics.h

#include "utils/wzhu_timing_statistics.h"
#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>

struct GR {
    struct alignas(64) VulkanAPI_ID_AtomicBucket {
        std::atomic<uint64_t> sum_nanoseconds{0};
        std::atomic<uint64_t> sample_count{0};
    };

    VulkanAPI_ID_AtomicBucket vulkan_api_id_buckets[kVulkanAPI_ID_BucketCount]{};
    std::atomic<uint64_t> present_count_in_window{0};
    std::atomic<uint64_t> gpu_delta_sum_nanoseconds{0};
    std::atomic<uint64_t> gpu_delta_sample_count{0};
    std::atomic<uint64_t> gpu_timestamp_last_nanoseconds{0};
    std::atomic<int> gpu_timestamp_initialized{0};
    std::atomic<int> gpu_timestamp_path_enabled{0};

    std::chrono::steady_clock::time_point report_window_start{std::chrono::steady_clock::now()};

    std::once_flag report_thread_once{};
    std::atomic<bool> report_thread_should_run{true};
};

static GR gr;

static int WZHU_readIntEnvironment(const char* environment_key, int default_value) {
    const char* raw = std::getenv(environment_key);
    if (raw == nullptr || raw[0] == '\0') {
        return default_value;
    }
    return std::atoi(raw);
}

static void WZHU_printVulkanApiReportLocked() {
    const auto now = std::chrono::steady_clock::now();
    const double elapsed_seconds =
        std::chrono::duration<double>(now - gr.report_window_start).count();
    if (elapsed_seconds <= 0.001) {
        return;
    }

    const uint64_t present_count =
        gr.present_count_in_window.exchange(0, std::memory_order_relaxed);
    const double cpu_frames_per_second =
        static_cast<double>(present_count) / elapsed_seconds;

    double gpu_frames_per_second = 0.0;
    const uint64_t gpu_delta_samples =
        gr.gpu_delta_sample_count.exchange(0, std::memory_order_relaxed);
    const uint64_t gpu_delta_sum =
        gr.gpu_delta_sum_nanoseconds.exchange(0, std::memory_order_relaxed);
    if (gpu_delta_samples > 0 && gpu_delta_sum > 0) {
        const double average_gpu_frame_nanoseconds =
            static_cast<double>(gpu_delta_sum) / static_cast<double>(gpu_delta_samples);
        if (average_gpu_frame_nanoseconds > 1.0) {
            gpu_frames_per_second = 1e9 / average_gpu_frame_nanoseconds;
        }
    } else if (gr.gpu_timestamp_path_enabled.load(std::memory_order_relaxed) == 0) {
        gpu_frames_per_second = cpu_frames_per_second;
    }

    std::fprintf(
        stderr,
        "[WZHU_profiling] window=%.2fs cpu_fps=%.1f gpu_fps=%.1f (gpu_ts=%s) |",
        elapsed_seconds,
        cpu_frames_per_second,
        gpu_frames_per_second,
        gr.gpu_timestamp_path_enabled.load(std::memory_order_relaxed) ? "on" : "off"
    );

    for (uint32_t api_id_index = 0;
         api_id_index < static_cast<uint32_t>(VulkanAPI_ID::Count);
         ++api_id_index) {
        const uint64_t sum_nanoseconds =
            gr.vulkan_api_id_buckets[api_id_index].sum_nanoseconds.exchange(0, std::memory_order_relaxed);
        const uint64_t sample_count =
            gr.vulkan_api_id_buckets[api_id_index].sample_count.exchange(0, std::memory_order_relaxed);
        if (sample_count == 0) {
            continue;
        }
        const double average_microseconds =
            static_cast<double>(sum_nanoseconds) / static_cast<double>(sample_count) / 1000.0;
        std::fprintf(
            stderr,
            " %s_avg_us=%.2f(n=%" PRIu64 ")",
            WZHU_getVulkanAPIName(static_cast<VulkanAPI_ID>(api_id_index)),
            average_microseconds,
            sample_count
        );
    }
    std::fprintf(stderr, "\n");
    std::fflush(stderr);

    gr.report_window_start = now;
}

static void WZHU_reportThreadLoop() {
    while (gr.report_thread_should_run.load(std::memory_order_relaxed)) {
        std::this_thread::sleep_for(
            std::chrono::milliseconds(static_cast<int>(kVulkanAPI_ReportIntervalSeconds * 1000))
        );
        WZHU_printVulkanApiReportLocked();
    }
}

void WZHU_startReportThreadOnce() {
    std::call_once(gr.report_thread_once, [] {
        std::thread(WZHU_reportThreadLoop).detach();
    });
}

void WZHU_recordVulkanAPINanoseconds(VulkanAPI_ID api_id, uint64_t elapsed_nanoseconds) {
    const uint32_t index = static_cast<uint32_t>(api_id);
    if (index >= static_cast<uint32_t>(VulkanAPI_ID::Count)) {
        return;
    }
    gr.vulkan_api_id_buckets[index].sum_nanoseconds.fetch_add(elapsed_nanoseconds, std::memory_order_relaxed);
    gr.vulkan_api_id_buckets[index].sample_count.fetch_add(1, std::memory_order_relaxed);
}

const char* WZHU_getVulkanAPIName(VulkanAPI_ID api_id) {
    switch (api_id) {
        case VulkanAPI_ID::CreateSwapchainKHR:
            return "vkCreateSwapchainKHR";
        case VulkanAPI_ID::DestroySwapchainKHR:
            return "vkDestroySwapchainKHR";
        case VulkanAPI_ID::AcquireNextImageKHR:
            return "vkAcquireNextImageKHR";
        case VulkanAPI_ID::AcquireNextImage2KHR:
            return "vkAcquireNextImage2KHR";
        case VulkanAPI_ID::QueuePresentKHR:
            return "vkQueuePresentKHR";
        case VulkanAPI_ID::QueueSubmit:
            return "vkQueueSubmit";
        case VulkanAPI_ID::QueueSubmit2:
            return "vkQueueSubmit2";
        case VulkanAPI_ID::QueueBindSparse:
            return "vkQueueBindSparse";
        case VulkanAPI_ID::GetSwapchainImagesKHR:
            return "vkGetSwapchainImagesKHR";
        case VulkanAPI_ID::GetPhysicalDeviceSurfaceCapabilitiesKHR:
            return "vkGetPhysicalDeviceSurfaceCapabilitiesKHR";
        case VulkanAPI_ID::GetPhysicalDeviceSurfaceFormatsKHR:
            return "vkGetPhysicalDeviceSurfaceFormatsKHR";
        case VulkanAPI_ID::GetPhysicalDeviceSurfacePresentModesKHR:
            return "vkGetPhysicalDeviceSurfacePresentModesKHR";
        case VulkanAPI_ID::GetPhysicalDeviceSurfaceSupportKHR:
            return "vkGetPhysicalDeviceSurfaceSupportKHR";
        case VulkanAPI_ID::CreateXcbSurfaceKHR:
            return "vkCreateXcbSurfaceKHR";
        case VulkanAPI_ID::CreateXlibSurfaceKHR:
            return "vkCreateXlibSurfaceKHR";
        case VulkanAPI_ID::CreateWaylandSurfaceKHR:
            return "vkCreateWaylandSurfaceKHR";
        case VulkanAPI_ID::CreateWin32SurfaceKHR:
            return "vkCreateWin32SurfaceKHR";
        case VulkanAPI_ID::CreateDisplayPlaneSurfaceKHR:
            return "vkCreateDisplayPlaneSurfaceKHR";
        case VulkanAPI_ID::GetPhysicalDeviceDisplayPropertiesKHR:
            return "vkGetPhysicalDeviceDisplayPropertiesKHR";
        case VulkanAPI_ID::GetPhysicalDeviceDisplayPlanePropertiesKHR:
            return "vkGetPhysicalDeviceDisplayPlanePropertiesKHR";
        case VulkanAPI_ID::GetDisplayModePropertiesKHR:
            return "vkGetDisplayModePropertiesKHR";
        case VulkanAPI_ID::GetDisplayPlaneSupportedDisplaysKHR:
            return "vkGetDisplayPlaneSupportedDisplaysKHR";
        case VulkanAPI_ID::GetDisplayPlaneCapabilitiesKHR:
            return "vkGetDisplayPlaneCapabilitiesKHR";
        case VulkanAPI_ID::CreateDisplayModeKHR:
            return "vkCreateDisplayModeKHR";
        default:
            return "?";
    }
}

uint32_t WZHU_getGpuTimestampStride() {
    const int stride = WZHU_readIntEnvironment("WZHU_GPU_TS_STRIDE", 1);
    return stride < 1 ? 1u : static_cast<uint32_t>(stride);
}

void WZHU_sampleGpuTimestamp(WZHU_DeviceDispatchTable* dispatch, VkDevice device) {
    if (dispatch == nullptr || !dispatch->hasCalibratedTimestamps ||
        dispatch->pfn_getCalibratedTimestampsKhr == nullptr) {
        return;
    }
    if (std::getenv("WZHU_DISABLE_GPU_TIMESTAMPS") != nullptr) {
        return;
    }

    static thread_local uint32_t present_stride_counter = 0;
    const uint32_t stride = WZHU_getGpuTimestampStride();
    ++present_stride_counter;
    if ((present_stride_counter % stride) != 0) {
        return;
    }

    VkCalibratedTimestampInfoKHR timestamp_info{};
    timestamp_info.sType = VK_STRUCTURE_TYPE_CALIBRATED_TIMESTAMP_INFO_KHR;
    timestamp_info.pNext = nullptr;
    timestamp_info.timeDomain = VK_TIME_DOMAIN_DEVICE_KHR;

    uint64_t timestamps[1]{};
    uint64_t max_deviations[1]{};
    const VkResult timestamp_result = dispatch->pfn_getCalibratedTimestampsKhr(
        device,
        1,
        &timestamp_info,
        timestamps,
        max_deviations
    );
    if (timestamp_result != VK_SUCCESS) {
        return;
    }

    const uint64_t current_timestamp = timestamps[0];
    const int previous_init =
        gr.gpu_timestamp_initialized.exchange(1, std::memory_order_acq_rel);
    if (previous_init == 0) {
        gr.gpu_timestamp_last_nanoseconds.store(current_timestamp, std::memory_order_relaxed);
        gr.gpu_timestamp_path_enabled.store(1, std::memory_order_relaxed);
        return;
    }
    const uint64_t previous_timestamp =
        gr.gpu_timestamp_last_nanoseconds.exchange(current_timestamp, std::memory_order_relaxed);
    if (current_timestamp > previous_timestamp) {
        const uint64_t delta_nanoseconds = current_timestamp - previous_timestamp;
        gr.gpu_delta_sum_nanoseconds.fetch_add(delta_nanoseconds, std::memory_order_relaxed);
        gr.gpu_delta_sample_count.fetch_add(1, std::memory_order_relaxed);
    }
}

void WZHU_recordPresent() {
    gr.present_count_in_window.fetch_add(1, std::memory_order_relaxed);
}
