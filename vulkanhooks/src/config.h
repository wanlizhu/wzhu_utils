#pragma once
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <memory>
#include <unordered_map>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>

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

struct WZHU_InstanceDispatchTable {
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr{};
    PFN_vkDestroyInstance pfn_vkDestroyInstance{};
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

extern std::unordered_map<VkInstance, std::unique_ptr<WZHU_InstanceDispatchTable>> g_instanceDispatchTableMap;
extern std::unordered_map<VkDevice, std::unique_ptr<WZHU_DeviceDispatchTable>> g_deviceDispatchTableMap;
extern std::unordered_map<VkQueue, VkDevice> g_queueDeviceMap;

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
    const auto instIt = g_instanceDispatchTableMap.find(instance);
    if (instIt == g_instanceDispatchTableMap.end()) {
        throw std::runtime_error(std::string("VkInstance has no layer dispatch table (") + WZHU_FileName(file) + ":" + std::to_string(line) + ")");
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
    const auto deviceIt = g_deviceDispatchTableMap.find(device);
    if (deviceIt == g_deviceDispatchTableMap.end()) {
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
#define LOAD_INSTANCE_FUNC(instance, symbol) reinterpret_cast<PFN_##symbol>(pfnNextGetInstanceProcAddr((instance), #symbol))
#define LOAD_DEVICE_FUNC(device, symbol) reinterpret_cast<PFN_##symbol>(pfnNextGetDeviceProcAddr((device), #symbol))
