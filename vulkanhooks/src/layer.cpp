// SPDX-License-Identifier: Apache-2.0
// Custom Vulkan layer: display/swapchain/submit CPU timing + rolling 2s report (CPU/GPU FPS).
// GPU FPS uses VK_KHR_calibrated_timestamps (VK_TIME_DOMAIN_DEVICE_KHR) between presents when enabled.

// vulkan.h must come before vk_layer.h so extension structs / PFNs from vulkan_core are visible.
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>

#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#if defined(_WIN32)
#define WZHU_LAYER_EXPORT __declspec(dllexport)
#else
#define WZHU_LAYER_EXPORT __attribute__((visibility("default")))
#endif

namespace {

constexpr uint32_t kStatCount = 32;
constexpr double kReportIntervalSec = 2.0;

enum StatId : uint32_t {
  Stat_CreateSwapchainKHR = 0,
  Stat_DestroySwapchainKHR,
  Stat_AcquireNextImageKHR,
  Stat_AcquireNextImage2KHR,
  Stat_QueuePresentKHR,
  Stat_QueueSubmit,
  Stat_QueueSubmit2,
  Stat_QueueBindSparse,
  Stat_GetSwapchainImagesKHR,
  Stat_GetPhysicalDeviceSurfaceCapabilitiesKHR,
  Stat_GetPhysicalDeviceSurfaceFormatsKHR,
  Stat_GetPhysicalDeviceSurfacePresentModesKHR,
  Stat_GetPhysicalDeviceSurfaceSupportKHR,
  Stat_CreateXcbSurfaceKHR,
  Stat_CreateXlibSurfaceKHR,
  Stat_CreateWaylandSurfaceKHR,
  Stat_CreateWin32SurfaceKHR,
  Stat_CreateDisplayPlaneSurfaceKHR,
  Stat_CreateAndroidSurfaceKHR,
  Stat_CreateMetalSurfaceEXT,
  Stat_GetPhysicalDeviceDisplayPropertiesKHR,
  Stat_GetPhysicalDeviceDisplayPlanePropertiesKHR,
  Stat_GetDisplayModePropertiesKHR,
  Stat_GetDisplayPlaneSupportedDisplaysKHR,
  Stat_GetDisplayPlaneCapabilitiesKHR,
  Stat_CreateDisplayModeKHR,
  Stat_Count
};

static_assert(Stat_Count <= kStatCount, "stat table size");

struct alignas(64) AtomicStat {
  std::atomic<uint64_t> sum_ns{0};
  std::atomic<uint64_t> count{0};
};

static AtomicStat g_stats[kStatCount];
static std::atomic<uint64_t> g_present_count_window{0};
static std::atomic<uint64_t> g_gpu_delta_sum_ns{0};
static std::atomic<uint64_t> g_gpu_delta_count{0};
static std::atomic<uint64_t> g_gpu_ts_last_ns{0};
static std::atomic<int> g_gpu_ts_initialized{0};
static std::atomic<int> g_gpu_ts_enabled{0};

static std::chrono::steady_clock::time_point g_window_start = std::chrono::steady_clock::now();

inline void record_ns(StatId id, uint64_t dt_ns) {
  const uint32_t i = static_cast<uint32_t>(id);
  if (i >= Stat_Count) return;
  g_stats[i].sum_ns.fetch_add(dt_ns, std::memory_order_relaxed);
  g_stats[i].count.fetch_add(1, std::memory_order_relaxed);
}

static const char* stat_name(StatId id) {
  switch (id) {
    case Stat_CreateSwapchainKHR:
      return "vkCreateSwapchainKHR";
    case Stat_DestroySwapchainKHR:
      return "vkDestroySwapchainKHR";
    case Stat_AcquireNextImageKHR:
      return "vkAcquireNextImageKHR";
    case Stat_AcquireNextImage2KHR:
      return "vkAcquireNextImage2KHR";
    case Stat_QueuePresentKHR:
      return "vkQueuePresentKHR";
    case Stat_QueueSubmit:
      return "vkQueueSubmit";
    case Stat_QueueSubmit2:
      return "vkQueueSubmit2";
    case Stat_QueueBindSparse:
      return "vkQueueBindSparse";
    case Stat_GetSwapchainImagesKHR:
      return "vkGetSwapchainImagesKHR";
    case Stat_GetPhysicalDeviceSurfaceCapabilitiesKHR:
      return "vkGetPhysicalDeviceSurfaceCapabilitiesKHR";
    case Stat_GetPhysicalDeviceSurfaceFormatsKHR:
      return "vkGetPhysicalDeviceSurfaceFormatsKHR";
    case Stat_GetPhysicalDeviceSurfacePresentModesKHR:
      return "vkGetPhysicalDeviceSurfacePresentModesKHR";
    case Stat_GetPhysicalDeviceSurfaceSupportKHR:
      return "vkGetPhysicalDeviceSurfaceSupportKHR";
    case Stat_CreateXcbSurfaceKHR:
      return "vkCreateXcbSurfaceKHR";
    case Stat_CreateXlibSurfaceKHR:
      return "vkCreateXlibSurfaceKHR";
    case Stat_CreateWaylandSurfaceKHR:
      return "vkCreateWaylandSurfaceKHR";
    case Stat_CreateWin32SurfaceKHR:
      return "vkCreateWin32SurfaceKHR";
    case Stat_CreateDisplayPlaneSurfaceKHR:
      return "vkCreateDisplayPlaneSurfaceKHR";
    case Stat_CreateAndroidSurfaceKHR:
      return "vkCreateAndroidSurfaceKHR";
    case Stat_CreateMetalSurfaceEXT:
      return "vkCreateMetalSurfaceEXT";
    case Stat_GetPhysicalDeviceDisplayPropertiesKHR:
      return "vkGetPhysicalDeviceDisplayPropertiesKHR";
    case Stat_GetPhysicalDeviceDisplayPlanePropertiesKHR:
      return "vkGetPhysicalDeviceDisplayPlanePropertiesKHR";
    case Stat_GetDisplayModePropertiesKHR:
      return "vkGetDisplayModePropertiesKHR";
    case Stat_GetDisplayPlaneSupportedDisplaysKHR:
      return "vkGetDisplayPlaneSupportedDisplaysKHR";
    case Stat_GetDisplayPlaneCapabilitiesKHR:
      return "vkGetDisplayPlaneCapabilitiesKHR";
    case Stat_CreateDisplayModeKHR:
      return "vkCreateDisplayModeKHR";
    default:
      return "?";
  }
}

static int env_int(const char* name, int default_value) {
  const char* v = std::getenv(name);
  if (!v || !*v) return default_value;
  return std::atoi(v);
}

static uint32_t gpu_ts_sample_stride() {
  const int s = env_int("WZHU_GPU_TS_STRIDE", 1);
  return s < 1 ? 1u : static_cast<uint32_t>(s);
}

static void print_report_locked() {
  const auto now = std::chrono::steady_clock::now();
  const double elapsed_sec =
      std::chrono::duration<double>(now - g_window_start).count();
  if (elapsed_sec <= 0.001) return;

  const uint64_t presents = g_present_count_window.exchange(0, std::memory_order_relaxed);
  const double cpu_fps = static_cast<double>(presents) / elapsed_sec;

  double gpu_fps = 0.0;
  const uint64_t gpu_deltas = g_gpu_delta_count.exchange(0, std::memory_order_relaxed);
  const uint64_t gpu_sum = g_gpu_delta_sum_ns.exchange(0, std::memory_order_relaxed);
  if (gpu_deltas > 0 && gpu_sum > 0) {
    const double avg_gpu_frame_ns = static_cast<double>(gpu_sum) / static_cast<double>(gpu_deltas);
    if (avg_gpu_frame_ns > 1.0) {
      gpu_fps = 1e9 / avg_gpu_frame_ns;
    }
  } else if (g_gpu_ts_enabled.load(std::memory_order_relaxed) == 0) {
    gpu_fps = cpu_fps;
  }

  std::fprintf(stderr,
               "[WZHU_profiling] window=%.2fs cpu_fps=%.1f gpu_fps=%.1f (gpu_ts=%s) |",
               elapsed_sec, cpu_fps, gpu_fps,
               g_gpu_ts_enabled.load(std::memory_order_relaxed) ? "on" : "off");

  for (uint32_t i = 0; i < static_cast<uint32_t>(Stat_Count); ++i) {
    const uint64_t sum = g_stats[i].sum_ns.exchange(0, std::memory_order_relaxed);
    const uint64_t cnt = g_stats[i].count.exchange(0, std::memory_order_relaxed);
    if (cnt == 0) continue;
    const double avg_us = static_cast<double>(sum) / static_cast<double>(cnt) / 1000.0;
    std::fprintf(stderr, " %s_avg_us=%.2f(n=%" PRIu64 ")", stat_name(static_cast<StatId>(i)), avg_us,
                 cnt);
  }
  std::fprintf(stderr, "\n");
  std::fflush(stderr);

  g_window_start = now;
}

static std::once_flag g_report_thread_once;
static std::atomic<bool> g_report_run{true};

static void report_thread_main() {
  while (g_report_run.load(std::memory_order_relaxed)) {
    std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(kReportIntervalSec * 1000)));
    print_report_locked();
  }
}

static void ensure_report_thread() {
  std::call_once(g_report_thread_once, [] {
    std::thread(report_thread_main).detach();
  });
}

struct InstanceDispatch {
  PFN_vkGetInstanceProcAddr get_instance_proc_addr{};
  PFN_vkDestroyInstance destroy_instance{};
  PFN_vkCreateDevice create_device{};
};

struct DeviceDispatch {
  PFN_vkGetDeviceProcAddr get_device_proc_addr{};
  PFN_vkDestroyDevice destroy_device{};
  PFN_vkGetDeviceQueue get_device_queue{};
  PFN_vkGetDeviceQueue2 get_device_queue2{};
  PFN_vkCreateSwapchainKHR create_swapchain_khr{};
  PFN_vkDestroySwapchainKHR destroy_swapchain_khr{};
  PFN_vkGetSwapchainImagesKHR get_swapchain_images_khr{};
  PFN_vkAcquireNextImageKHR acquire_next_image_khr{};
  PFN_vkAcquireNextImage2KHR acquire_next_image2_khr{};
  PFN_vkQueuePresentKHR queue_present_khr{};
  PFN_vkQueueSubmit queue_submit{};
  PFN_vkQueueSubmit2 queue_submit2{};
  PFN_vkQueueBindSparse queue_bind_sparse{};
  PFN_vkGetCalibratedTimestampsKHR get_calibrated_timestamps_khr{};

  VkDevice device{};
  VkPhysicalDevice physical_device{};
  bool has_calibrated_timestamps{false};
};

static std::shared_mutex g_instance_mutex;
static std::unordered_map<VkInstance, std::unique_ptr<InstanceDispatch>> g_instance_dispatch;

static std::shared_mutex g_device_mutex;
static std::unordered_map<VkDevice, std::unique_ptr<DeviceDispatch>> g_device_dispatch;

static std::shared_mutex g_queue_mutex;
static std::unordered_map<VkQueue, VkDevice> g_queue_to_device;

static void register_queue(VkQueue queue, VkDevice device) {
  if (queue == VK_NULL_HANDLE || device == VK_NULL_HANDLE) return;
  std::unique_lock<std::shared_mutex> lock(g_queue_mutex);
  g_queue_to_device[queue] = device;
}

static void unregister_queues_for_device(VkDevice device) {
  if (device == VK_NULL_HANDLE) return;
  std::unique_lock<std::shared_mutex> lock(g_queue_mutex);
  for (auto it = g_queue_to_device.begin(); it != g_queue_to_device.end();) {
    if (it->second == device) {
      it = g_queue_to_device.erase(it);
    } else {
      ++it;
    }
  }
}

static VkDevice lookup_device_for_queue(VkQueue queue) {
  std::shared_lock<std::shared_mutex> lock(g_queue_mutex);
  const auto it = g_queue_to_device.find(queue);
  if (it == g_queue_to_device.end()) return VK_NULL_HANDLE;
  return it->second;
}

static InstanceDispatch* get_instance_dispatch(VkInstance instance) {
  std::shared_lock<std::shared_mutex> lock(g_instance_mutex);
  auto it = g_instance_dispatch.find(instance);
  if (it == g_instance_dispatch.end()) return nullptr;
  return it->second.get();
}

static DeviceDispatch* get_device_dispatch(VkDevice device) {
  std::shared_lock<std::shared_mutex> lock(g_device_mutex);
  auto it = g_device_dispatch.find(device);
  if (it == g_device_dispatch.end()) return nullptr;
  return it->second.get();
}

static const VkLayerInstanceCreateInfo* get_instance_chain(const VkInstanceCreateInfo* pCreateInfo) {
  for (const VkBaseInStructure* p = reinterpret_cast<const VkBaseInStructure*>(pCreateInfo->pNext); p;
       p = reinterpret_cast<const VkBaseInStructure*>(p->pNext)) {
    if (p->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO) {
      return reinterpret_cast<const VkLayerInstanceCreateInfo*>(p);
    }
  }
  return nullptr;
}

static const VkLayerDeviceCreateInfo* get_device_chain(const VkDeviceCreateInfo* pCreateInfo) {
  for (const VkBaseInStructure* p = reinterpret_cast<const VkBaseInStructure*>(pCreateInfo->pNext); p;
       p = reinterpret_cast<const VkBaseInStructure*>(p->pNext)) {
    if (p->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO) {
      return reinterpret_cast<const VkLayerDeviceCreateInfo*>(p);
    }
  }
  return nullptr;
}

static bool extension_enabled(const char* name, uint32_t count, const char* const* names) {
  for (uint32_t i = 0; i < count; ++i) {
    if (names[i] && std::strcmp(names[i], name) == 0) return true;
  }
  return false;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateSwapchainKHR(VkDevice device,
                                                           const VkSwapchainCreateInfoKHR* pCreateInfo,
                                                           const VkAllocationCallbacks* pAllocator,
                                                           VkSwapchainKHR* pSwapchain) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->create_swapchain_khr) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->create_swapchain_khr(device, pCreateInfo, pAllocator, pSwapchain);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_CreateSwapchainKHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR void VKAPI_CALL InterceptDestroySwapchainKHR(VkDevice device, VkSwapchainKHR swapchain,
                                                        const VkAllocationCallbacks* pAllocator) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->destroy_swapchain_khr) return;
  const auto t0 = std::chrono::steady_clock::now();
  d->destroy_swapchain_khr(device, swapchain, pAllocator);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_DestroySwapchainKHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptGetSwapchainImagesKHR(VkDevice device, VkSwapchainKHR swapchain,
                                                              uint32_t* pSwapchainImageCount,
                                                              VkImage* pSwapchainImages) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->get_swapchain_images_khr) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r =
      d->get_swapchain_images_khr(device, swapchain, pSwapchainImageCount, pSwapchainImages);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_GetSwapchainImagesKHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptAcquireNextImageKHR(VkDevice device, VkSwapchainKHR swapchain,
                                                          uint64_t timeout, VkSemaphore semaphore,
                                                          VkFence fence, uint32_t* pImageIndex) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->acquire_next_image_khr) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r =
      d->acquire_next_image_khr(device, swapchain, timeout, semaphore, fence, pImageIndex);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_AcquireNextImageKHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptAcquireNextImage2KHR(VkDevice device,
                                                             const VkAcquireNextImageInfoKHR* pAcquireInfo,
                                                             uint32_t* pImageIndex) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->acquire_next_image2_khr) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->acquire_next_image2_khr(device, pAcquireInfo, pImageIndex);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_AcquireNextImage2KHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

static void maybe_record_gpu_timestamp(DeviceDispatch* d, VkDevice device) {
  if (!d || !d->has_calibrated_timestamps || !d->get_calibrated_timestamps_khr) return;
  if (std::getenv("WZHU_DISABLE_GPU_TIMESTAMPS")) return;

  static thread_local uint32_t s_stride_counter = 0;
  const uint32_t stride = gpu_ts_sample_stride();
  ++s_stride_counter;
  if ((s_stride_counter % stride) != 0) return;

  VkCalibratedTimestampInfoKHR info{};
  info.sType = VK_STRUCTURE_TYPE_CALIBRATED_TIMESTAMP_INFO_KHR;
  info.pNext = nullptr;
  info.timeDomain = VK_TIME_DOMAIN_DEVICE_KHR;

  uint64_t ts[1]{};
  uint64_t deviations[1]{};
  const VkResult tr = d->get_calibrated_timestamps_khr(device, 1, &info, ts, deviations);
  if (tr != VK_SUCCESS) return;

  const uint64_t cur = ts[0];
  const int was = g_gpu_ts_initialized.exchange(1, std::memory_order_acq_rel);
  if (was == 0) {
    g_gpu_ts_last_ns.store(cur, std::memory_order_relaxed);
    g_gpu_ts_enabled.store(1, std::memory_order_relaxed);
    return;
  }
  const uint64_t prev = g_gpu_ts_last_ns.exchange(cur, std::memory_order_relaxed);
  if (cur > prev) {
    const uint64_t delta = cur - prev;
    g_gpu_delta_sum_ns.fetch_add(delta, std::memory_order_relaxed);
    g_gpu_delta_count.fetch_add(1, std::memory_order_relaxed);
  }
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueuePresentKHR(VkQueue queue, const VkPresentInfoKHR* pPresentInfo) {
  const VkDevice device = lookup_device_for_queue(queue);
  auto* d = get_device_dispatch(device);
  if (!d || !d->queue_present_khr) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->queue_present_khr(queue, pPresentInfo);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_QueuePresentKHR,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  if (r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR) {
    g_present_count_window.fetch_add(1, std::memory_order_relaxed);
    maybe_record_gpu_timestamp(d, device);
  }
  return r;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueSubmit(VkQueue queue, uint32_t submitCount,
                                                   const VkSubmitInfo* pSubmits, VkFence fence) {
  const VkDevice device = lookup_device_for_queue(queue);
  auto* d = get_device_dispatch(device);
  if (!d || !d->queue_submit) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->queue_submit(queue, submitCount, pSubmits, fence);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_QueueSubmit, std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueSubmit2(VkQueue queue, uint32_t submitCount,
                                                    const VkSubmitInfo2* pSubmits, VkFence fence) {
  const VkDevice device = lookup_device_for_queue(queue);
  auto* d = get_device_dispatch(device);
  if (!d || !d->queue_submit2) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->queue_submit2(queue, submitCount, pSubmits, fence);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_QueueSubmit2,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptQueueBindSparse(VkQueue queue, uint32_t bindInfoCount,
                                                      const VkBindSparseInfo* pBindInfo, VkFence fence) {
  const VkDevice device = lookup_device_for_queue(queue);
  auto* d = get_device_dispatch(device);
  if (!d || !d->queue_bind_sparse) return VK_ERROR_INITIALIZATION_FAILED;
  const auto t0 = std::chrono::steady_clock::now();
  const VkResult r = d->queue_bind_sparse(queue, bindInfoCount, pBindInfo, fence);
  const auto t1 = std::chrono::steady_clock::now();
  record_ns(Stat_QueueBindSparse,
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
  return r;
}

VKAPI_ATTR void VKAPI_CALL InterceptGetDeviceQueue(VkDevice device, uint32_t queueFamilyIndex,
                                                   uint32_t queueIndex, VkQueue* pQueue) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->get_device_queue) return;
  d->get_device_queue(device, queueFamilyIndex, queueIndex, pQueue);
  if (pQueue && *pQueue != VK_NULL_HANDLE) {
    register_queue(*pQueue, device);
  }
}

VKAPI_ATTR void VKAPI_CALL InterceptGetDeviceQueue2(VkDevice device, const VkDeviceQueueInfo2* pQueueInfo,
                                                    VkQueue* pQueue) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->get_device_queue2) return;
  d->get_device_queue2(device, pQueueInfo, pQueue);
  if (pQueue && *pQueue != VK_NULL_HANDLE) {
    register_queue(*pQueue, device);
  }
}

// Instance hooks: surface + display-related (timing only)
struct InstanceExtras {
  PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR get_surface_caps{};
  PFN_vkGetPhysicalDeviceSurfaceFormatsKHR get_surface_formats{};
  PFN_vkGetPhysicalDeviceSurfacePresentModesKHR get_surface_present_modes{};
  PFN_vkGetPhysicalDeviceSurfaceSupportKHR get_surface_support{};
  PFN_vkCreateXcbSurfaceKHR create_xcb_surface{};
  PFN_vkCreateXlibSurfaceKHR create_xlib_surface{};
  PFN_vkCreateWaylandSurfaceKHR create_wayland_surface{};
#if defined(VK_USE_PLATFORM_WIN32_KHR)
  PFN_vkCreateWin32SurfaceKHR create_win32_surface{};
#endif
  PFN_vkCreateDisplayPlaneSurfaceKHR create_display_plane_surface{};
#if defined(VK_USE_PLATFORM_ANDROID_KHR)
  PFN_vkCreateAndroidSurfaceKHR create_android_surface{};
#endif
#if defined(VK_USE_PLATFORM_METAL_EXT)
  PFN_vkCreateMetalSurfaceEXT create_metal_surface{};
#endif
  PFN_vkGetPhysicalDeviceDisplayPropertiesKHR get_display_props{};
  PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR get_display_plane_props{};
  PFN_vkGetDisplayModePropertiesKHR get_display_mode_props{};
  PFN_vkGetDisplayPlaneSupportedDisplaysKHR get_display_plane_supported_displays{};
  PFN_vkGetDisplayPlaneCapabilitiesKHR get_display_plane_caps{};
  PFN_vkCreateDisplayModeKHR create_display_mode{};
};

static std::unordered_map<VkInstance, std::unique_ptr<InstanceExtras>> g_instance_extras;

static InstanceExtras* get_instance_extras(VkInstance instance) {
  std::shared_lock<std::shared_mutex> lock(g_instance_mutex);
  auto it = g_instance_extras.find(instance);
  if (it == g_instance_extras.end()) return nullptr;
  return it->second.get();
}

#define WZHU_INTERCEPT_INSTANCE_RESULT(InterceptName, Member, stat, Args, call) \
  VKAPI_ATTR VkResult VKAPI_CALL Intercept##InterceptName Args { \
    auto* ex = get_instance_extras(Instance); \
    if (!ex || !ex->Member) return VK_ERROR_INITIALIZATION_FAILED; \
    const auto t0 = std::chrono::steady_clock::now(); \
    const VkResult r = ex->Member call; \
    const auto t1 = std::chrono::steady_clock::now(); \
    record_ns(stat, std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count()); \
    return r; \
  }

#define WZHU_INTERCEPT_INSTANCE_VOID(Name, stat, Args, call)                                   \
  VKAPI_ATTR void VKAPI_CALL Intercept##Name Args {                                            \
    auto* ex = get_instance_extras(Instance);                                                  \
    if (!ex || !ex->Name) return;                                                              \
    const auto t0 = std::chrono::steady_clock::now();                                        \
    ex->Name call;                                                                             \
    const auto t1 = std::chrono::steady_clock::now();                                         \
    record_ns(stat, std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());  \
  }

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfaceCapabilitiesKHR, get_surface_caps, Stat_GetPhysicalDeviceSurfaceCapabilitiesKHR,
    (VkInstance Instance, VkPhysicalDevice physicalDevice, VkSurfaceKHR surface,
     VkSurfaceCapabilitiesKHR* pSurfaceCapabilities),
    (physicalDevice, surface, pSurfaceCapabilities))

WZHU_INTERCEPT_INSTANCE_RESULT(GetPhysicalDeviceSurfaceFormatsKHR, get_surface_formats,
                               Stat_GetPhysicalDeviceSurfaceFormatsKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice,
                                VkSurfaceKHR surface, uint32_t* pSurfaceFormatCount,
                                VkSurfaceFormatKHR* pSurfaceFormats),
                               (physicalDevice, surface, pSurfaceFormatCount, pSurfaceFormats))

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfacePresentModesKHR, get_surface_present_modes,
    Stat_GetPhysicalDeviceSurfacePresentModesKHR,
    (VkInstance Instance, VkPhysicalDevice physicalDevice, VkSurfaceKHR surface,
     uint32_t* pPresentModeCount, VkPresentModeKHR* pPresentModes),
    (physicalDevice, surface, pPresentModeCount, pPresentModes))

WZHU_INTERCEPT_INSTANCE_RESULT(GetPhysicalDeviceSurfaceSupportKHR, get_surface_support,
                               Stat_GetPhysicalDeviceSurfaceSupportKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice,
                                uint32_t queueFamilyIndex, VkSurfaceKHR surface, VkBool32* pSupported),
                               (physicalDevice, queueFamilyIndex, surface, pSupported))

#if defined(VK_USE_PLATFORM_XCB_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateXcbSurfaceKHR, create_xcb_surface, Stat_CreateXcbSurfaceKHR,
                               (VkInstance Instance, const VkXcbSurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateXlibSurfaceKHR, create_xlib_surface, Stat_CreateXlibSurfaceKHR,
                               (VkInstance Instance, const VkXlibSurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateWaylandSurfaceKHR, create_wayland_surface, Stat_CreateWaylandSurfaceKHR,
                               (VkInstance Instance, const VkWaylandSurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateWin32SurfaceKHR, create_win32_surface, Stat_CreateWin32SurfaceKHR,
                               (VkInstance Instance, const VkWin32SurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

WZHU_INTERCEPT_INSTANCE_RESULT(CreateDisplayPlaneSurfaceKHR, create_display_plane_surface,
                               Stat_CreateDisplayPlaneSurfaceKHR,
                               (VkInstance Instance, const VkDisplaySurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))

#if defined(VK_USE_PLATFORM_ANDROID_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateAndroidSurfaceKHR, create_android_surface, Stat_CreateAndroidSurfaceKHR,
                               (VkInstance Instance, const VkAndroidSurfaceCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

#if defined(VK_USE_PLATFORM_METAL_EXT)
WZHU_INTERCEPT_INSTANCE_RESULT(CreateMetalSurfaceEXT, create_metal_surface, Stat_CreateMetalSurfaceEXT,
                               (VkInstance Instance, const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkSurfaceKHR* pSurface),
                               (Instance, pCreateInfo, pAllocator, pSurface))
#endif

WZHU_INTERCEPT_INSTANCE_RESULT(GetPhysicalDeviceDisplayPropertiesKHR, get_display_props,
                               Stat_GetPhysicalDeviceDisplayPropertiesKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice,
                                uint32_t* pPropertyCount, VkDisplayPropertiesKHR* pProperties),
                               (physicalDevice, pPropertyCount, pProperties))

WZHU_INTERCEPT_INSTANCE_RESULT(GetPhysicalDeviceDisplayPlanePropertiesKHR, get_display_plane_props,
                               Stat_GetPhysicalDeviceDisplayPlanePropertiesKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice,
                                uint32_t* pPropertyCount, VkDisplayPlanePropertiesKHR* pProperties),
                               (physicalDevice, pPropertyCount, pProperties))

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetDisplayModePropertiesKHR, get_display_mode_props, Stat_GetDisplayModePropertiesKHR,
    (VkInstance Instance, VkPhysicalDevice physicalDevice, VkDisplayKHR display, uint32_t* pPropertyCount,
     VkDisplayModePropertiesKHR* pProperties),
    (physicalDevice, display, pPropertyCount, pProperties))

WZHU_INTERCEPT_INSTANCE_RESULT(GetDisplayPlaneSupportedDisplaysKHR, get_display_plane_supported_displays,
                               Stat_GetDisplayPlaneSupportedDisplaysKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice, uint32_t planeIndex,
                                uint32_t* pDisplayCount, VkDisplayKHR* pDisplays),
                               (physicalDevice, planeIndex, pDisplayCount, pDisplays))

WZHU_INTERCEPT_INSTANCE_RESULT(GetDisplayPlaneCapabilitiesKHR, get_display_plane_caps,
                               Stat_GetDisplayPlaneCapabilitiesKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice,
                                VkDisplayModeKHR mode, uint32_t planeIndex,
                                VkDisplayPlaneCapabilitiesKHR* pCapabilities),
                               (physicalDevice, mode, planeIndex, pCapabilities))

WZHU_INTERCEPT_INSTANCE_RESULT(CreateDisplayModeKHR, create_display_mode, Stat_CreateDisplayModeKHR,
                               (VkInstance Instance, VkPhysicalDevice physicalDevice, VkDisplayKHR display,
                                const VkDisplayModeCreateInfoKHR* pCreateInfo,
                                const VkAllocationCallbacks* pAllocator, VkDisplayModeKHR* pMode),
                               (physicalDevice, display, pCreateInfo, pAllocator, pMode))

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateInstance(const VkInstanceCreateInfo* pCreateInfo,
                                                      const VkAllocationCallbacks* pAllocator,
                                                      VkInstance* pInstance) {
  const VkLayerInstanceCreateInfo* chain = get_instance_chain(pCreateInfo);
  if (!chain || chain->function != VK_LAYER_LINK_INFO || !chain->u.pLayerInfo) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }
  const PFN_vkGetInstanceProcAddr next_gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
  const PFN_vkCreateInstance next_create =
      reinterpret_cast<PFN_vkCreateInstance>(next_gipa(VK_NULL_HANDLE, "vkCreateInstance"));
  if (!next_create) return VK_ERROR_INITIALIZATION_FAILED;

  ensure_report_thread();

  const VkResult r = next_create(pCreateInfo, pAllocator, pInstance);
  if (r != VK_SUCCESS || !pInstance || *pInstance == VK_NULL_HANDLE) return r;

  auto disp = std::make_unique<InstanceDispatch>();
  disp->get_instance_proc_addr = next_gipa;
  disp->destroy_instance =
      reinterpret_cast<PFN_vkDestroyInstance>(next_gipa(*pInstance, "vkDestroyInstance"));
  disp->create_device =
      reinterpret_cast<PFN_vkCreateDevice>(next_gipa(*pInstance, "vkCreateDevice"));

  {
    std::unique_lock<std::shared_mutex> lock(g_instance_mutex);
    g_instance_dispatch[*pInstance] = std::move(disp);
  }

  auto extras = std::make_unique<InstanceExtras>();
  extras->get_surface_caps = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"));
  extras->get_surface_formats = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceSurfaceFormatsKHR"));
  extras->get_surface_present_modes = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceSurfacePresentModesKHR"));
  extras->get_surface_support = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceSurfaceSupportKHR"));
#if defined(VK_USE_PLATFORM_XCB_KHR)
  extras->create_xcb_surface = reinterpret_cast<PFN_vkCreateXcbSurfaceKHR>(
      next_gipa(*pInstance, "vkCreateXcbSurfaceKHR"));
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
  extras->create_xlib_surface = reinterpret_cast<PFN_vkCreateXlibSurfaceKHR>(
      next_gipa(*pInstance, "vkCreateXlibSurfaceKHR"));
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
  extras->create_wayland_surface = reinterpret_cast<PFN_vkCreateWaylandSurfaceKHR>(
      next_gipa(*pInstance, "vkCreateWaylandSurfaceKHR"));
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
  extras->create_win32_surface = reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(
      next_gipa(*pInstance, "vkCreateWin32SurfaceKHR"));
#endif
  extras->create_display_plane_surface = reinterpret_cast<PFN_vkCreateDisplayPlaneSurfaceKHR>(
      next_gipa(*pInstance, "vkCreateDisplayPlaneSurfaceKHR"));
#if defined(VK_USE_PLATFORM_ANDROID_KHR)
  extras->create_android_surface = reinterpret_cast<PFN_vkCreateAndroidSurfaceKHR>(
      next_gipa(*pInstance, "vkCreateAndroidSurfaceKHR"));
#endif
#if defined(VK_USE_PLATFORM_METAL_EXT)
  extras->create_metal_surface =
      reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(next_gipa(*pInstance, "vkCreateMetalSurfaceEXT"));
#endif
  extras->get_display_props = reinterpret_cast<PFN_vkGetPhysicalDeviceDisplayPropertiesKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceDisplayPropertiesKHR"));
  extras->get_display_plane_props = reinterpret_cast<PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR>(
      next_gipa(*pInstance, "vkGetPhysicalDeviceDisplayPlanePropertiesKHR"));
  extras->get_display_mode_props = reinterpret_cast<PFN_vkGetDisplayModePropertiesKHR>(
      next_gipa(*pInstance, "vkGetDisplayModePropertiesKHR"));
  extras->get_display_plane_supported_displays = reinterpret_cast<PFN_vkGetDisplayPlaneSupportedDisplaysKHR>(
      next_gipa(*pInstance, "vkGetDisplayPlaneSupportedDisplaysKHR"));
  extras->get_display_plane_caps = reinterpret_cast<PFN_vkGetDisplayPlaneCapabilitiesKHR>(
      next_gipa(*pInstance, "vkGetDisplayPlaneCapabilitiesKHR"));
  extras->create_display_mode = reinterpret_cast<PFN_vkCreateDisplayModeKHR>(
      next_gipa(*pInstance, "vkCreateDisplayModeKHR"));

  {
    std::unique_lock<std::shared_mutex> lock(g_instance_mutex);
    g_instance_extras[*pInstance] = std::move(extras);
  }

  return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL InterceptDestroyInstance(VkInstance instance,
                                                    const VkAllocationCallbacks* pAllocator) {
  auto* disp = get_instance_dispatch(instance);
  if (!disp || !disp->destroy_instance) return;
  disp->destroy_instance(instance, pAllocator);
  {
    std::unique_lock<std::shared_mutex> lock(g_instance_mutex);
    g_instance_dispatch.erase(instance);
    g_instance_extras.erase(instance);
  }
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateDevice(VkPhysicalDevice physicalDevice,
                                                     const VkDeviceCreateInfo* pCreateInfo,
                                                     const VkAllocationCallbacks* pAllocator,
                                                     VkDevice* pDevice) {
  const VkLayerDeviceCreateInfo* chain = get_device_chain(pCreateInfo);
  if (!chain || chain->function != VK_LAYER_LINK_INFO || !chain->u.pLayerInfo) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }
  const PFN_vkGetInstanceProcAddr next_gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
  const PFN_vkGetDeviceProcAddr next_gdpa = chain->u.pLayerInfo->pfnNextGetDeviceProcAddr;
  const PFN_vkCreateDevice next_create =
      reinterpret_cast<PFN_vkCreateDevice>(next_gipa(VK_NULL_HANDLE, "vkCreateDevice"));
  if (!next_create) return VK_ERROR_INITIALIZATION_FAILED;

  VkDeviceCreateInfo patched = *pCreateInfo;
  std::vector<const char*> extensions;
  extensions.reserve(patched.enabledExtensionCount + 4u);
  for (uint32_t i = 0; i < patched.enabledExtensionCount; ++i) {
    extensions.push_back(patched.ppEnabledExtensionNames[i]);
  }
  const bool need_calib =
      !extension_enabled(VK_KHR_CALIBRATED_TIMESTAMPS_EXTENSION_NAME, patched.enabledExtensionCount,
                         patched.ppEnabledExtensionNames);
  if (need_calib) {
    extensions.push_back(VK_KHR_CALIBRATED_TIMESTAMPS_EXTENSION_NAME);
  }
  patched.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
  patched.ppEnabledExtensionNames = extensions.data();

  // Khronos headers no longer ship VkPhysicalDeviceCalibratedTimestampFeaturesKHR; enabling the
  // extension is sufficient for vkGetCalibratedTimestampsKHR on conformant drivers.

  ensure_report_thread();

  const VkResult r = next_create(physicalDevice, &patched, pAllocator, pDevice);
  if (r != VK_SUCCESS || !pDevice || *pDevice == VK_NULL_HANDLE) return r;

  auto dd = std::make_unique<DeviceDispatch>();
  dd->get_device_proc_addr = next_gdpa;
  dd->device = *pDevice;
  dd->physical_device = physicalDevice;
  dd->destroy_device = reinterpret_cast<PFN_vkDestroyDevice>(next_gdpa(*pDevice, "vkDestroyDevice"));
  dd->get_device_queue = reinterpret_cast<PFN_vkGetDeviceQueue>(next_gdpa(*pDevice, "vkGetDeviceQueue"));
  dd->get_device_queue2 = reinterpret_cast<PFN_vkGetDeviceQueue2>(next_gdpa(*pDevice, "vkGetDeviceQueue2"));
  dd->create_swapchain_khr =
      reinterpret_cast<PFN_vkCreateSwapchainKHR>(next_gdpa(*pDevice, "vkCreateSwapchainKHR"));
  dd->destroy_swapchain_khr =
      reinterpret_cast<PFN_vkDestroySwapchainKHR>(next_gdpa(*pDevice, "vkDestroySwapchainKHR"));
  dd->get_swapchain_images_khr =
      reinterpret_cast<PFN_vkGetSwapchainImagesKHR>(next_gdpa(*pDevice, "vkGetSwapchainImagesKHR"));
  dd->acquire_next_image_khr =
      reinterpret_cast<PFN_vkAcquireNextImageKHR>(next_gdpa(*pDevice, "vkAcquireNextImageKHR"));
  dd->acquire_next_image2_khr =
      reinterpret_cast<PFN_vkAcquireNextImage2KHR>(next_gdpa(*pDevice, "vkAcquireNextImage2KHR"));
  dd->queue_present_khr =
      reinterpret_cast<PFN_vkQueuePresentKHR>(next_gdpa(*pDevice, "vkQueuePresentKHR"));
  dd->queue_submit = reinterpret_cast<PFN_vkQueueSubmit>(next_gdpa(*pDevice, "vkQueueSubmit"));
  dd->queue_submit2 = reinterpret_cast<PFN_vkQueueSubmit2>(next_gdpa(*pDevice, "vkQueueSubmit2"));
  dd->queue_bind_sparse =
      reinterpret_cast<PFN_vkQueueBindSparse>(next_gdpa(*pDevice, "vkQueueBindSparse"));
  dd->get_calibrated_timestamps_khr =
      reinterpret_cast<PFN_vkGetCalibratedTimestampsKHR>(next_gdpa(*pDevice, "vkGetCalibratedTimestampsKHR"));

  dd->has_calibrated_timestamps = (dd->get_calibrated_timestamps_khr != nullptr);

  {
    std::unique_lock<std::shared_mutex> lock(g_device_mutex);
    g_device_dispatch[*pDevice] = std::move(dd);
  }
  return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL InterceptDestroyDevice(VkDevice device, const VkAllocationCallbacks* pAllocator) {
  auto* d = get_device_dispatch(device);
  if (!d || !d->destroy_device) return;
  unregister_queues_for_device(device);
  d->destroy_device(device, pAllocator);
  std::unique_lock<std::shared_mutex> lock(g_device_mutex);
  g_device_dispatch.erase(device);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetDeviceProcAddr(VkDevice device, const char* pName);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetInstanceProcAddr(VkInstance instance,
                                                                      const char* pName) {
  if (!pName) return nullptr;

#define WZHU_IF_NAME(name, fn) \
  if (std::strcmp(pName, name) == 0) return reinterpret_cast<PFN_vkVoidFunction>(fn)

  WZHU_IF_NAME("vkCreateInstance", InterceptCreateInstance);
  WZHU_IF_NAME("vkDestroyInstance", InterceptDestroyInstance);
  WZHU_IF_NAME("vkCreateDevice", InterceptCreateDevice);
  WZHU_IF_NAME("vkDestroyDevice", InterceptDestroyDevice);
  WZHU_IF_NAME("vkGetInstanceProcAddr", InterceptGetInstanceProcAddr);
  WZHU_IF_NAME("vkGetDeviceProcAddr", InterceptGetDeviceProcAddr);

  WZHU_IF_NAME("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", InterceptGetPhysicalDeviceSurfaceCapabilitiesKHR);
  WZHU_IF_NAME("vkGetPhysicalDeviceSurfaceFormatsKHR", InterceptGetPhysicalDeviceSurfaceFormatsKHR);
  WZHU_IF_NAME("vkGetPhysicalDeviceSurfacePresentModesKHR", InterceptGetPhysicalDeviceSurfacePresentModesKHR);
  WZHU_IF_NAME("vkGetPhysicalDeviceSurfaceSupportKHR", InterceptGetPhysicalDeviceSurfaceSupportKHR);

#if defined(VK_USE_PLATFORM_XCB_KHR)
  WZHU_IF_NAME("vkCreateXcbSurfaceKHR", InterceptCreateXcbSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
  WZHU_IF_NAME("vkCreateXlibSurfaceKHR", InterceptCreateXlibSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
  WZHU_IF_NAME("vkCreateWaylandSurfaceKHR", InterceptCreateWaylandSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
  WZHU_IF_NAME("vkCreateWin32SurfaceKHR", InterceptCreateWin32SurfaceKHR);
#endif
  WZHU_IF_NAME("vkCreateDisplayPlaneSurfaceKHR", InterceptCreateDisplayPlaneSurfaceKHR);
#if defined(VK_USE_PLATFORM_ANDROID_KHR)
  WZHU_IF_NAME("vkCreateAndroidSurfaceKHR", InterceptCreateAndroidSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_METAL_EXT)
  WZHU_IF_NAME("vkCreateMetalSurfaceEXT", InterceptCreateMetalSurfaceEXT);
#endif

  WZHU_IF_NAME("vkGetPhysicalDeviceDisplayPropertiesKHR", InterceptGetPhysicalDeviceDisplayPropertiesKHR);
  WZHU_IF_NAME("vkGetPhysicalDeviceDisplayPlanePropertiesKHR",
               InterceptGetPhysicalDeviceDisplayPlanePropertiesKHR);
  WZHU_IF_NAME("vkGetDisplayModePropertiesKHR", InterceptGetDisplayModePropertiesKHR);
  WZHU_IF_NAME("vkGetDisplayPlaneSupportedDisplaysKHR", InterceptGetDisplayPlaneSupportedDisplaysKHR);
  WZHU_IF_NAME("vkGetDisplayPlaneCapabilitiesKHR", InterceptGetDisplayPlaneCapabilitiesKHR);
  WZHU_IF_NAME("vkCreateDisplayModeKHR", InterceptCreateDisplayModeKHR);

#undef WZHU_IF_NAME

  auto* disp = get_instance_dispatch(instance);
  if (!disp || !disp->get_instance_proc_addr) return nullptr;
  return disp->get_instance_proc_addr(instance, pName);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetDeviceProcAddr(VkDevice device, const char* pName) {
  if (!pName) return nullptr;

#define WZHU_DEV_IF_NAME(name, fn) \
  if (std::strcmp(pName, name) == 0) return reinterpret_cast<PFN_vkVoidFunction>(fn)

  WZHU_DEV_IF_NAME("vkGetDeviceProcAddr", InterceptGetDeviceProcAddr);
  WZHU_DEV_IF_NAME("vkDestroyDevice", InterceptDestroyDevice);
  WZHU_DEV_IF_NAME("vkGetDeviceQueue", InterceptGetDeviceQueue);
  WZHU_DEV_IF_NAME("vkGetDeviceQueue2", InterceptGetDeviceQueue2);
  WZHU_DEV_IF_NAME("vkCreateSwapchainKHR", InterceptCreateSwapchainKHR);
  WZHU_DEV_IF_NAME("vkDestroySwapchainKHR", InterceptDestroySwapchainKHR);
  WZHU_DEV_IF_NAME("vkGetSwapchainImagesKHR", InterceptGetSwapchainImagesKHR);
  WZHU_DEV_IF_NAME("vkAcquireNextImageKHR", InterceptAcquireNextImageKHR);
  WZHU_DEV_IF_NAME("vkAcquireNextImage2KHR", InterceptAcquireNextImage2KHR);
  WZHU_DEV_IF_NAME("vkQueuePresentKHR", InterceptQueuePresentKHR);
  WZHU_DEV_IF_NAME("vkQueueSubmit", InterceptQueueSubmit);
  WZHU_DEV_IF_NAME("vkQueueSubmit2", InterceptQueueSubmit2);
  WZHU_DEV_IF_NAME("vkQueueBindSparse", InterceptQueueBindSparse);

#undef WZHU_DEV_IF_NAME

  auto* d = get_device_dispatch(device);
  if (!d || !d->get_device_proc_addr) return nullptr;
  return d->get_device_proc_addr(device, pName);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL InterceptGetPhysicalDeviceProcAddr(VkInstance instance,
                                                                            const char* pName) {
  return InterceptGetInstanceProcAddr(instance, pName);
}

}  // namespace

extern "C" {

WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(
    VkNegotiateLayerInterface* pVersionStruct) {
  if (!pVersionStruct || pVersionStruct->sType != LAYER_NEGOTIATE_INTERFACE_STRUCT) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }
  if (pVersionStruct->loaderLayerInterfaceVersion < MIN_SUPPORTED_LOADER_LAYER_INTERFACE_VERSION) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }
  if (pVersionStruct->loaderLayerInterfaceVersion > CURRENT_LOADER_LAYER_INTERFACE_VERSION) {
    pVersionStruct->loaderLayerInterfaceVersion = CURRENT_LOADER_LAYER_INTERFACE_VERSION;
  }
  pVersionStruct->pfnGetInstanceProcAddr = InterceptGetInstanceProcAddr;
  pVersionStruct->pfnGetDeviceProcAddr = InterceptGetDeviceProcAddr;
  pVersionStruct->pfnGetPhysicalDeviceProcAddr = InterceptGetPhysicalDeviceProcAddr;
  return VK_SUCCESS;
}

WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance,
                                                                                 const char* pName) {
  return InterceptGetInstanceProcAddr(instance, pName);
}

WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device,
                                                                                const char* pName) {
  return InterceptGetDeviceProcAddr(device, pName);
}

WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceLayerProperties(uint32_t* pPropertyCount,
                                                                                    VkLayerProperties* pProperties) {
  static const VkLayerProperties layer_props = {
      "VK_LAYER_WZHU_profiling",
      VK_MAKE_API_VERSION(0, 1, 3, 280),
      1,
      "WZHU profiling layer (swapchain/display/submit timing)",
  };
  if (!pPropertyCount) return VK_INCOMPLETE;
  if (!pProperties) {
    *pPropertyCount = 1;
    return VK_SUCCESS;
  }
  if (*pPropertyCount < 1) {
    *pPropertyCount = 1;
    return VK_INCOMPLETE;
  }
  *pPropertyCount = 1;
  pProperties[0] = layer_props;
  return VK_SUCCESS;
}

WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceExtensionProperties(
    const char* pLayerName, uint32_t* pPropertyCount, VkExtensionProperties* pProperties) {
  if (pLayerName && std::strcmp(pLayerName, "VK_LAYER_WZHU_profiling") != 0) {
    return VK_ERROR_LAYER_NOT_PRESENT;
  }
  if (pPropertyCount) *pPropertyCount = 0;
  return VK_SUCCESS;
}

WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceLayerProperties(
    VkPhysicalDevice physicalDevice, uint32_t* pPropertyCount, VkLayerProperties* pProperties) {
  (void)physicalDevice;
  return vkEnumerateInstanceLayerProperties(pPropertyCount, pProperties);
}

WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceExtensionProperties(
    VkPhysicalDevice physicalDevice, const char* pLayerName, uint32_t* pPropertyCount,
    VkExtensionProperties* pProperties) {
  (void)physicalDevice;
  return vkEnumerateInstanceExtensionProperties(pLayerName, pPropertyCount, pProperties);
}

}  // extern "C"
