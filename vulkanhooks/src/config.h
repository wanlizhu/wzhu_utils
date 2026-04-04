#pragma once
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <memory>
#include <map>
#include <unordered_map>
#include <cstring>
#include <string>
#include <mutex>
#include <stdexcept>
#include <type_traits>
#include <cstddef>
#include <cstdarg>
#include <cstdio>
#include <vector>

#if defined(_WIN32)
#define WZHU_LAYER_EXPORT __declspec(dllexport)
#else
#define WZHU_LAYER_EXPORT __attribute__((visibility("default")))
#endif

template<typename... T>
inline void __UnusedVariables__(T&&...) {}
#define UNUSED_VARS(...) __UnusedVariables__(__VA_ARGS__)

#define HOOK_VULKAN_SURFACE_API
#define HOOK_VULKAN_SWAPCHAIN_API
#define DUMP_HOOKED_API

// Dispatch slots only for Vulkan commands this layer implements (IMPL_vk*) and forwards. Other Vulkan
// entry points can be called directly when linking the loader (Vulkan::Vulkan), same as a normal app,
// without adding fields here.
struct WZHU_InstanceDispatchTable {
    // VkInstance returned from pfnNextCreateInstance; use for downstream calls when the loader passes a
    // different dispatchable handle for the same logical instance.
    VkInstance canonicalInstance{};
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr{};
    PFN_vkDestroyInstance pfn_vkDestroyInstance{};
    PFN_vkEnumeratePhysicalDevices pfn_vkEnumeratePhysicalDevices{};
    PFN_vkCreateDevice pfn_vkCreateDevice{};

    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR pfn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR{};
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR pfn_vkGetPhysicalDeviceSurfaceFormatsKHR{};
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR pfn_vkGetPhysicalDeviceSurfacePresentModesKHR{};
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR pfn_vkGetPhysicalDeviceSurfaceSupportKHR{};
#if defined(VK_USE_PLATFORM_XCB_KHR)
    PFN_vkCreateXcbSurfaceKHR pfn_vkCreateXcbSurfaceKHR{};
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    PFN_vkCreateXlibSurfaceKHR pfn_vkCreateXlibSurfaceKHR{};
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    PFN_vkCreateWaylandSurfaceKHR pfn_vkCreateWaylandSurfaceKHR{};
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    PFN_vkCreateWin32SurfaceKHR pfn_vkCreateWin32SurfaceKHR{};
#endif
    PFN_vkCreateDisplayPlaneSurfaceKHR pfn_vkCreateDisplayPlaneSurfaceKHR{};
    PFN_vkGetPhysicalDeviceDisplayPropertiesKHR pfn_vkGetPhysicalDeviceDisplayPropertiesKHR{};
    PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR pfn_vkGetPhysicalDeviceDisplayPlanePropertiesKHR{};
    PFN_vkGetDisplayModePropertiesKHR pfn_vkGetDisplayModePropertiesKHR{};
    PFN_vkGetDisplayPlaneSupportedDisplaysKHR pfn_vkGetDisplayPlaneSupportedDisplaysKHR{};
    PFN_vkGetDisplayPlaneCapabilitiesKHR pfn_vkGetDisplayPlaneCapabilitiesKHR{};
    PFN_vkCreateDisplayModeKHR pfn_vkCreateDisplayModeKHR{};
};

struct WZHU_DeviceDispatchTable {
    VkDevice device{};
    VkPhysicalDevice physicalDevice{};

    PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr{};
    PFN_vkDestroyDevice pfn_vkDestroyDevice{};
    PFN_vkGetDeviceQueue pfn_vkGetDeviceQueue{};
    PFN_vkGetDeviceQueue2 pfn_vkGetDeviceQueue2{};
    PFN_vkCreateSwapchainKHR pfn_vkCreateSwapchainKHR{};
    PFN_vkDestroySwapchainKHR pfn_vkDestroySwapchainKHR{};
    PFN_vkGetSwapchainImagesKHR pfn_vkGetSwapchainImagesKHR{};
    PFN_vkAcquireNextImageKHR pfn_vkAcquireNextImageKHR{};
    PFN_vkAcquireNextImage2KHR pfn_vkAcquireNextImage2KHR{};
    PFN_vkQueuePresentKHR pfn_vkQueuePresentKHR{};
    PFN_vkQueueSubmit pfn_vkQueueSubmit{};
    PFN_vkQueueSubmit2 pfn_vkQueueSubmit2{};
    PFN_vkQueueBindSparse pfn_vkQueueBindSparse{};
};

extern std::mutex g_instanceDispatchTableMutex;
extern VkInstance g_selectedInstance;
extern PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr;
extern std::unordered_map<VkInstance, std::shared_ptr<WZHU_InstanceDispatchTable>> g_instanceToDispatchTableMap;
extern std::unordered_map<VkPhysicalDevice, VkInstance> g_physicalDeviceToInstanceMap;
extern std::unordered_map<VkDevice, std::unique_ptr<WZHU_DeviceDispatchTable>> g_deviceToDispatchTableMap;
extern std::unordered_map<VkQueue, VkDevice> g_queueToDeviceMap;

inline const char* WZHU_FileName(const char* path) {
    const char* base = path;
    for (const char* p = path; *p != '\0'; ++p) {
        if (*p == '/' || *p == '\\') {
            base = p + 1;
        }
    }
    return base;
}

template<typename MemberPointer_T>
inline WZHU_InstanceDispatchTable* getInstanceDispatchTable(
    VkInstance instance,
    MemberPointer_T requiredFunction,
    const char* file,
    uint32_t line
) {
    std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
    const auto instIt = g_instanceToDispatchTableMap.find(instance);
    if (instIt == g_instanceToDispatchTableMap.end()) {
        throw std::runtime_error(std::string("VkInstance has no dispatch table (") + WZHU_FileName(file) + ":" + std::to_string(line) + ")");
    }

    WZHU_InstanceDispatchTable* dispatchTable = instIt->second.get();
    if (dispatchTable->*requiredFunction == nullptr) {
        throw std::runtime_error(std::string("Required instance function is null (") + WZHU_FileName(file) + ":" + std::to_string(line) + ")");
    }

    return dispatchTable;
}

template<typename MemberPointer_T>
inline WZHU_DeviceDispatchTable* getDeviceDispatchTable(
    VkDevice device,
    MemberPointer_T requiredFunction,
    const char* file,
    uint32_t line
) {
    const auto deviceIt = g_deviceToDispatchTableMap.find(device);
    if (deviceIt == g_deviceToDispatchTableMap.end()) {
        throw std::runtime_error(std::string("VkDevice has no dispatch table (") + WZHU_FileName(file) + ":" + std::to_string(line) + ")");
    }

    WZHU_DeviceDispatchTable* dispatchTable = deviceIt->second.get();
    if (dispatchTable == nullptr || dispatchTable->*requiredFunction == nullptr) {
        throw std::runtime_error(std::string("Required device function is null (") + WZHU_FileName(file) + ":" + std::to_string(line) + ")");
    }

    return dispatchTable;
}

#define GET_INSTANCE_DISPATCH_TABLE(instance, symbol) getInstanceDispatchTable((instance), &WZHU_InstanceDispatchTable::pfn_##symbol, __FILE__, __LINE__)
#define GET_DEVICE_DISPATCH_TABLE(device, symbol) getDeviceDispatchTable((device), &WZHU_DeviceDispatchTable::pfn_##symbol, __FILE__, __LINE__)
#define LOAD_INSTANCE_FUNC(pfn_loader, instance, symbol) reinterpret_cast<PFN_##symbol>(pfn_loader((instance), #symbol))
#define LOAD_DEVICE_FUNC(pfn_loader, device, symbol) reinterpret_cast<PFN_##symbol>(pfn_loader((device), #symbol))
#define INSTANCE_FUNC(symbol) reinterpret_cast<PFN_##symbol>(g_pfn_vkGetInstanceProcAddr(g_selectedInstance, #symbol))

#define WZHU_LOG(...) fprintf(stderr, "[wzhu] " __VA_ARGS__)
#define VK_ASSERT(result) if (result != VK_SUCCESS) { WZHU_LOG("VkResult: %s\n", WZHU_VkResult(result)); } 
