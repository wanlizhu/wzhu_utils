#include "hook_dispatch.h"
#include "hook_device.h"
#include "hook_instance.h"

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetInstanceProcAddr(
    VkInstance instance,
    const char* name
) {
    if (name == nullptr) { return nullptr; }
    if (std::strcmp(name, "vkCreateInstance") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateInstance); }
    if (std::strcmp(name, "vkDestroyInstance") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkDestroyInstance); }
    if (std::strcmp(name, "vkEnumeratePhysicalDevices") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkEnumeratePhysicalDevices); }
    if (std::strcmp(name, "vkCreateDevice") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateDevice); }
    if (std::strcmp(name, "vkDestroyDevice") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkDestroyDevice); }
    if (std::strcmp(name, "vkGetInstanceProcAddr") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetInstanceProcAddr); }
    if (std::strcmp(name, "vkGetDeviceProcAddr") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDeviceProcAddr); }
    if (std::strcmp(name, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR); }
    if (std::strcmp(name, "vkGetPhysicalDeviceSurfaceFormatsKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR); }
    if (std::strcmp(name, "vkGetPhysicalDeviceSurfacePresentModesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR); }
    if (std::strcmp(name, "vkGetPhysicalDeviceSurfaceSupportKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceSurfaceSupportKHR); }
    if (std::strcmp(name, "vkCreateDisplayPlaneSurfaceKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateDisplayPlaneSurfaceKHR); }
    if (std::strcmp(name, "vkGetPhysicalDeviceDisplayPropertiesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceDisplayPropertiesKHR); }
    if (std::strcmp(name, "vkGetPhysicalDeviceDisplayPlanePropertiesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR); }
    if (std::strcmp(name, "vkGetDisplayModePropertiesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDisplayModePropertiesKHR); }
    if (std::strcmp(name, "vkGetDisplayPlaneSupportedDisplaysKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDisplayPlaneSupportedDisplaysKHR); }
    if (std::strcmp(name, "vkGetDisplayPlaneCapabilitiesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDisplayPlaneCapabilitiesKHR); }
    if (std::strcmp(name, "vkCreateDisplayModeKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateDisplayModeKHR); }
#if defined(VK_USE_PLATFORM_XCB_KHR)
    if (std::strcmp(name, "vkCreateXcbSurfaceKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateXcbSurfaceKHR); }
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    if (std::strcmp(name, "vkCreateXlibSurfaceKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateXlibSurfaceKHR); }
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    if (std::strcmp(name, "vkCreateWaylandSurfaceKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateWaylandSurfaceKHR); }
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    if (std::strcmp(name, "vkCreateWin32SurfaceKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateWin32SurfaceKHR); }
#endif

    WZHU_InstanceDispatchTable* dispatchTable = nullptr;
    {
        std::lock_guard<std::mutex> mapLock(g_instanceDispatchTableMutex);
        auto instIt = g_instanceToDispatchTableMap.find(instance);
        if (instIt == g_instanceToDispatchTableMap.end()) {
            dispatchTable = nullptr;
        } else {
            dispatchTable = instIt->second.get();
        }
    }

    if (dispatchTable == nullptr) {
        PFN_vkGetInstanceProcAddr nextGipa = WZHU_getNextGIPA();
        if (nextGipa != nullptr) {
            return reinterpret_cast<PFN_vkVoidFunction>(nextGipa(instance, name));
        }
        return nullptr;
    }
    
    if (dispatchTable->pfn_vkGetInstanceProcAddr == nullptr) {
        return nullptr;
    }

    return dispatchTable->pfn_vkGetInstanceProcAddr(instance, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetDeviceProcAddr(
    VkDevice device,
    const char* name
) {
    if (name == nullptr) { return nullptr; }
    if (std::strcmp(name, "vkGetDeviceProcAddr") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDeviceProcAddr); }
    if (std::strcmp(name, "vkDestroyDevice") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkDestroyDevice); }
    if (std::strcmp(name, "vkGetDeviceQueue") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDeviceQueue); }
    if (std::strcmp(name, "vkGetDeviceQueue2") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetDeviceQueue2); }
    if (std::strcmp(name, "vkCreateSwapchainKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkCreateSwapchainKHR); }
    if (std::strcmp(name, "vkDestroySwapchainKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkDestroySwapchainKHR); }
    if (std::strcmp(name, "vkGetSwapchainImagesKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkGetSwapchainImagesKHR); }
    if (std::strcmp(name, "vkAcquireNextImageKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkAcquireNextImageKHR); }
    if (std::strcmp(name, "vkAcquireNextImage2KHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkAcquireNextImage2KHR); }
    if (std::strcmp(name, "vkQueuePresentKHR") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkQueuePresentKHR); }
    if (std::strcmp(name, "vkQueueSubmit") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkQueueSubmit); }
    if (std::strcmp(name, "vkQueueSubmit2") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkQueueSubmit2); }
    if (std::strcmp(name, "vkQueueBindSparse") == 0) { return reinterpret_cast<PFN_vkVoidFunction>(IMPL_vkQueueBindSparse); }

    auto deviceTableIt = g_deviceToDispatchTableMap.find(device);
    if (deviceTableIt == g_deviceToDispatchTableMap.end()) {
        return nullptr;
    }
    
    WZHU_DeviceDispatchTable* dispatchTable = deviceTableIt->second.get();
    if (dispatchTable->pfn_vkGetDeviceProcAddr == nullptr) {
        return nullptr;
    }

    return dispatchTable->pfn_vkGetDeviceProcAddr(device, name);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL IMPL_vkGetPhysicalDeviceProcAddr(
    VkInstance instance,
    const char* name
) {
    return IMPL_vkGetInstanceProcAddr(instance, name);
}
