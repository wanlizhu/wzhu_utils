#include "hook_instance.h"

static const VkLayerInstanceCreateInfo* findLayerInstanceCreateInfo(const VkInstanceCreateInfo* createInfo) {
    for (const VkBaseInStructure* chain = reinterpret_cast<const VkBaseInStructure*>(createInfo->pNext);
        chain != nullptr;
        chain = reinterpret_cast<const VkBaseInStructure*>(chain->pNext)
    ) {
        if (chain->sType != VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO) {
            continue;
        }
        const auto* layerInfo = reinterpret_cast<const VkLayerInstanceCreateInfo*>(chain);
        // Loader 1.4+ may chain several LOADER_INSTANCE_CREATE_INFO nodes (e.g. VK_LOADER_FEATURES) before
        // the VK_LAYER_LINK_INFO node; the first match is not always the dispatch chain.
        if (layerInfo->function == VK_LAYER_LINK_INFO && layerInfo->u.pLayerInfo != nullptr) {
            return layerInfo;
        }
    }
    return nullptr;
}

static const VkLayerDeviceCreateInfo* findLayerDeviceCreateInfo(const VkDeviceCreateInfo* createInfo) {
    for (const VkBaseInStructure* chain = reinterpret_cast<const VkBaseInStructure*>(createInfo->pNext);
        chain != nullptr;
        chain = reinterpret_cast<const VkBaseInStructure*>(chain->pNext)
    ) {
        if (chain->sType != VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO) {
            continue;
        }
        const auto* layerInfo = reinterpret_cast<const VkLayerDeviceCreateInfo*>(chain);
        if (layerInfo->function == VK_LAYER_LINK_INFO && layerInfo->u.pLayerInfo != nullptr) {
            return layerInfo;
        }
    }
    return nullptr;
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateInstance(
    const VkInstanceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkInstance* outInstance
) {
    const VkLayerInstanceCreateInfo* layerInstanceCreateInfo = findLayerInstanceCreateInfo(createInfo);
    if (layerInstanceCreateInfo == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    PFN_vkGetInstanceProcAddr pfnNextGetInstanceProcAddr = layerInstanceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkCreateInstance pfnNextCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(pfnNextGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance"));
    if (pfnNextCreateInstance == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    VkLayerInstanceCreateInfo* layerInstanceLink = const_cast<VkLayerInstanceCreateInfo*>(layerInstanceCreateInfo);
    if (layerInstanceLink->u.pLayerInfo != nullptr) {
        layerInstanceLink->u.pLayerInfo = layerInstanceLink->u.pLayerInfo->pNext;
    }

    VkResult createResult = pfnNextCreateInstance(createInfo, allocator, outInstance);
    if (createResult != VK_SUCCESS || outInstance == nullptr || *outInstance == VK_NULL_HANDLE) {
        return createResult;
    }

    // Register the instance before LOAD_INSTANCE_FUNC: pfnNextGetInstanceProcAddr or the loader may
    // re-enter IMPL_vkGetInstanceProcAddr / surface entry points; GET_INSTANCE_DISPATCH_TABLE and the
    // tail of IMPL_vkGetInstanceProcAddr require this map entry.
    auto dispatchTable = std::make_unique<WZHU_InstanceDispatchTable>();
    dispatchTable->pfn_vkGetInstanceProcAddr = pfnNextGetInstanceProcAddr;
    g_instanceDispatchTableMap[*outInstance] = std::move(dispatchTable);

    WZHU_InstanceDispatchTable* const dt = g_instanceDispatchTableMap[*outInstance].get();
    dt->pfn_vkDestroyInstance = LOAD_INSTANCE_FUNC(*outInstance, vkDestroyInstance);
    dt->pfn_vkCreateDevice = LOAD_INSTANCE_FUNC(*outInstance, vkCreateDevice);
    dt->pfn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
    dt->pfn_vkGetPhysicalDeviceSurfaceFormatsKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceSurfaceFormatsKHR);
    dt->pfn_vkGetPhysicalDeviceSurfacePresentModesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceSurfacePresentModesKHR);
    dt->pfn_vkGetPhysicalDeviceSurfaceSupportKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceSurfaceSupportKHR);
    dt->pfn_vkCreateDisplayPlaneSurfaceKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateDisplayPlaneSurfaceKHR);
    dt->pfn_vkGetPhysicalDeviceDisplayPropertiesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceDisplayPropertiesKHR);
    dt->pfn_vkGetPhysicalDeviceDisplayPlanePropertiesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetPhysicalDeviceDisplayPlanePropertiesKHR);
    dt->pfn_vkGetDisplayModePropertiesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetDisplayModePropertiesKHR);
    dt->pfn_vkGetDisplayPlaneSupportedDisplaysKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetDisplayPlaneSupportedDisplaysKHR);
    dt->pfn_vkGetDisplayPlaneCapabilitiesKHR = LOAD_INSTANCE_FUNC(*outInstance, vkGetDisplayPlaneCapabilitiesKHR);
    dt->pfn_vkCreateDisplayModeKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateDisplayModeKHR);
#if defined(VK_USE_PLATFORM_XCB_KHR)
    dt->pfn_vkCreateXcbSurfaceKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateXcbSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    dt->pfn_vkCreateXlibSurfaceKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateXlibSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    dt->pfn_vkCreateWaylandSurfaceKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateWaylandSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    dt->pfn_vkCreateWin32SurfaceKHR = LOAD_INSTANCE_FUNC(*outInstance, vkCreateWin32SurfaceKHR);
#endif

    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator
) {
    auto instIt = g_instanceDispatchTableMap.find(instance);
    if (instIt == g_instanceDispatchTableMap.end()) {
        return;
    }

    WZHU_InstanceDispatchTable* dispatchTable = instIt->second.get();
    if (dispatchTable->pfn_vkDestroyInstance == nullptr) {
        return;
    }

    dispatchTable->pfn_vkDestroyInstance(instance, allocator);
    g_instanceDispatchTableMap.erase(instance);
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkDevice* outDevice
) {
    const VkLayerDeviceCreateInfo* layerDeviceCreateInfo = findLayerDeviceCreateInfo(createInfo);
    if (layerDeviceCreateInfo == nullptr || 
        layerDeviceCreateInfo->function != VK_LAYER_LINK_INFO ||
        layerDeviceCreateInfo->u.pLayerInfo == nullptr
    ) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    PFN_vkGetInstanceProcAddr pfnNextGetInstanceProcAddr = layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkGetDeviceProcAddr pfnNextGetDeviceProcAddr = layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    PFN_vkCreateDevice pfnNextCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(pfnNextGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice"));
    if (pfnNextCreateDevice == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    VkLayerDeviceCreateInfo* layerDeviceLink = const_cast<VkLayerDeviceCreateInfo*>(layerDeviceCreateInfo);
    if (layerDeviceLink->u.pLayerInfo != nullptr) {
        layerDeviceLink->u.pLayerInfo = layerDeviceLink->u.pLayerInfo->pNext;
    }

    VkResult createResult = pfnNextCreateDevice(physicalDevice, createInfo, allocator, outDevice);
    if (createResult != VK_SUCCESS || outDevice == nullptr || *outDevice == VK_NULL_HANDLE) {
        return createResult;
    }

    auto dispatchTable = std::make_unique<WZHU_DeviceDispatchTable>();
    dispatchTable->pfn_vkGetDeviceProcAddr = pfnNextGetDeviceProcAddr;
    dispatchTable->device = *outDevice;
    dispatchTable->physicalDevice = physicalDevice;
    dispatchTable->pfn_vkDestroyDevice = LOAD_DEVICE_FUNC(*outDevice, vkDestroyDevice);
    dispatchTable->pfn_vkGetDeviceQueue = LOAD_DEVICE_FUNC(*outDevice, vkGetDeviceQueue);
    dispatchTable->pfn_vkGetDeviceQueue2 = LOAD_DEVICE_FUNC(*outDevice, vkGetDeviceQueue2);
    dispatchTable->pfn_vkCreateSwapchainKHR = LOAD_DEVICE_FUNC(*outDevice, vkCreateSwapchainKHR);
    dispatchTable->pfn_vkDestroySwapchainKHR = LOAD_DEVICE_FUNC(*outDevice, vkDestroySwapchainKHR);
    dispatchTable->pfn_vkGetSwapchainImagesKHR = LOAD_DEVICE_FUNC(*outDevice, vkGetSwapchainImagesKHR);
    dispatchTable->pfn_vkAcquireNextImageKHR = LOAD_DEVICE_FUNC(*outDevice, vkAcquireNextImageKHR);
    dispatchTable->pfn_vkAcquireNextImage2KHR = LOAD_DEVICE_FUNC(*outDevice, vkAcquireNextImage2KHR);
    dispatchTable->pfn_vkQueuePresentKHR = LOAD_DEVICE_FUNC(*outDevice, vkQueuePresentKHR);
    dispatchTable->pfn_vkQueueSubmit = LOAD_DEVICE_FUNC(*outDevice, vkQueueSubmit);
    dispatchTable->pfn_vkQueueSubmit2 = LOAD_DEVICE_FUNC(*outDevice, vkQueueSubmit2);
    dispatchTable->pfn_vkQueueBindSparse = LOAD_DEVICE_FUNC(*outDevice, vkQueueBindSparse);

    g_deviceDispatchTableMap[*outDevice] = std::move(dispatchTable);

    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator
) {
    auto deviceTableIt = g_deviceDispatchTableMap.find(device);
    if (deviceTableIt == g_deviceDispatchTableMap.end()) {
        return;
    }

    WZHU_DeviceDispatchTable* dispatchTable = deviceTableIt->second.get();
    if (dispatchTable->pfn_vkDestroyDevice == nullptr) {
        return;
    }

    for (auto iter = g_queueDeviceMap.begin(); iter != g_queueDeviceMap.end();) {
        if (iter->second == device) {
            iter = g_queueDeviceMap.erase(iter);
        } else {
            ++iter;
        }
    }
    
    dispatchTable->pfn_vkDestroyDevice(device, allocator);
    g_deviceDispatchTableMap.erase(device);
}


#ifdef HOOK_VULKAN_SURFACE_API
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    VkSurfaceCapabilitiesKHR* capabilities
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceSurfaceCapabilitiesKHR)->pfn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        physicalDevice,
        surface,
        capabilities
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* formatCount,
    VkSurfaceFormatKHR* formats
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceSurfaceFormatsKHR)->pfn_vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        formatCount,
        formats
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* modeCount,
    VkPresentModeKHR* modes
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceSurfacePresentModesKHR)->pfn_vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        modeCount,
        modes
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceSupportKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    uint32_t queueFamilyIndex,
    VkSurfaceKHR surface,
    VkBool32* supported
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceSurfaceSupportKHR)->pfn_vkGetPhysicalDeviceSurfaceSupportKHR(
        physicalDevice,
        queueFamilyIndex,
        surface,
        supported
    );
}

#if defined(VK_USE_PLATFORM_XCB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXcbSurfaceKHR(
    VkInstance instance,
    const VkXcbSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateXcbSurfaceKHR)->pfn_vkCreateXcbSurfaceKHR(
        instance,
        createInfo,
        allocator,
        outSurface
    );
}
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateXlibSurfaceKHR(
    VkInstance instance,
    const VkXlibSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateXlibSurfaceKHR)->pfn_vkCreateXlibSurfaceKHR(
        instance,
        createInfo,
        allocator,
        outSurface
    );
}
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWaylandSurfaceKHR(
    VkInstance instance,
    const VkWaylandSurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateWaylandSurfaceKHR)->pfn_vkCreateWaylandSurfaceKHR(
        instance,
        createInfo,
        allocator,
        outSurface
    );
}
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateWin32SurfaceKHR(
    VkInstance instance,
    const VkWin32SurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateWin32SurfaceKHR)->pfn_vkCreateWin32SurfaceKHR(
        instance,
        createInfo,
        allocator,
        outSurface
    );
}
#endif

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayPlaneSurfaceKHR(
    VkInstance instance,
    const VkDisplaySurfaceCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* outSurface
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateDisplayPlaneSurfaceKHR)->pfn_vkCreateDisplayPlaneSurfaceKHR(
        instance,
        createInfo,
        allocator,
        outSurface
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPropertiesKHR* properties
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceDisplayPropertiesKHR)->pfn_vkGetPhysicalDeviceDisplayPropertiesKHR(
        physicalDevice,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPlanePropertiesKHR* properties
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetPhysicalDeviceDisplayPlanePropertiesKHR)->pfn_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
        physicalDevice,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayModePropertiesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    uint32_t* propertyCount,
    VkDisplayModePropertiesKHR* properties
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetDisplayModePropertiesKHR)->pfn_vkGetDisplayModePropertiesKHR(
        physicalDevice,
        display,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneSupportedDisplaysKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    uint32_t planeIndex,
    uint32_t* displayCount,
    VkDisplayKHR* displays
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetDisplayPlaneSupportedDisplaysKHR)->pfn_vkGetDisplayPlaneSupportedDisplaysKHR(
        physicalDevice,
        planeIndex,
        displayCount,
        displays
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneCapabilitiesKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkDisplayModeKHR mode,
    uint32_t planeIndex,
    VkDisplayPlaneCapabilitiesKHR* capabilities
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkGetDisplayPlaneCapabilitiesKHR)->pfn_vkGetDisplayPlaneCapabilitiesKHR(
        physicalDevice,
        mode,
        planeIndex,
        capabilities
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayModeKHR(
    VkInstance instance,
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    const VkDisplayModeCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkDisplayModeKHR* outMode
) {
    return GET_INSTANCE_DISPATCH_TABLE(instance, vkCreateDisplayModeKHR)->pfn_vkCreateDisplayModeKHR(
        physicalDevice,
        display,
        createInfo,
        allocator,
        outMode
    );
}
#endif // HOOK_VULKAN_SURFACE_API