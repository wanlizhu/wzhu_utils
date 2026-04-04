#include "hook_instance.h"

#include <mutex>

// GIPA = GetInstanceProcAddr 
struct WZHU_NextGIPA_Scope {
    inline static std::mutex s_mutex{};
    inline static PFN_vkGetInstanceProcAddr s_next = nullptr;
    PFN_vkGetInstanceProcAddr previous{};

    static PFN_vkGetInstanceProcAddr next() {
        std::lock_guard<std::mutex> lock(s_mutex);
        return s_next;
    }

    WZHU_NextGIPA_Scope(PFN_vkGetInstanceProcAddr next) {
        std::lock_guard<std::mutex> lock(s_mutex);
        previous = s_next;
        s_next = next;
    }

    ~WZHU_NextGIPA_Scope() {
        std::lock_guard<std::mutex> lock(s_mutex);
        s_next = previous;
    }
    
    WZHU_NextGIPA_Scope(const WZHU_NextGIPA_Scope&) = delete;
    WZHU_NextGIPA_Scope& operator=(const WZHU_NextGIPA_Scope&) = delete;
};

PFN_vkGetInstanceProcAddr WZHU_getNextGIPA() {
    return WZHU_NextGIPA_Scope::next();
}

static VkInstance WZHU_instanceForPhysicalDevice(VkPhysicalDevice physicalDevice) {
    std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
    const auto it = g_physicalDeviceToInstanceMap.find(physicalDevice);
    if (it == g_physicalDeviceToInstanceMap.end()) {
        return VK_NULL_HANDLE;
    }
    return it->second;
}

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

    {
        WZHU_NextGIPA_Scope nextGipaScope(pfnNextGetInstanceProcAddr);
        VkResult createResult = pfnNextCreateInstance(createInfo, allocator, outInstance);
        if (createResult != VK_SUCCESS || outInstance == nullptr || *outInstance == VK_NULL_HANDLE) {
            return createResult;
        }

        // Register the instance before LOAD_INSTANCE_FUNC: pfnNextGetInstanceProcAddr or the loader may
        // re-enter IMPL_vkGetInstanceProcAddr before the map exists; WZHU_NextGIPA_Scope covers forwarding.
        auto dispatchTable = std::make_shared<WZHU_InstanceDispatchTable>();
        dispatchTable->pfn_vkGetInstanceProcAddr = pfnNextGetInstanceProcAddr;
        WZHU_InstanceDispatchTable* dt = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
            g_instanceToDispatchTableMap[*outInstance] = dispatchTable;
            dt = g_instanceToDispatchTableMap[*outInstance].get();
        }
        dt->canonicalInstance = *outInstance;
        dt->pfn_vkDestroyInstance = LOAD_INSTANCE_FUNC(*outInstance, vkDestroyInstance);
        dt->pfn_vkEnumeratePhysicalDevices = LOAD_INSTANCE_FUNC(*outInstance, vkEnumeratePhysicalDevices);
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
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkEnumeratePhysicalDevices(
    VkInstance instance,
    uint32_t* physicalDeviceCount,
    VkPhysicalDevice* physicalDevices
) {
    VkInstance tableKey = instance;
    {
        std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
        const auto instIt = g_instanceToDispatchTableMap.find(instance);
        if (instIt != g_instanceToDispatchTableMap.end() && instIt->second->canonicalInstance != VK_NULL_HANDLE) {
            tableKey = instIt->second->canonicalInstance;
        }
    }
    const PFN_vkEnumeratePhysicalDevices pfnEnum =
        GET_INSTANCE_DISPATCH_TABLE(tableKey, vkEnumeratePhysicalDevices)->pfn_vkEnumeratePhysicalDevices;
    const VkResult result = pfnEnum(instance, physicalDeviceCount, physicalDevices);
    if (result != VK_SUCCESS) {
        return result;
    }
    if (physicalDevices == nullptr || physicalDeviceCount == nullptr) {
        return result;
    }
    const uint32_t count = *physicalDeviceCount;
    std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
    for (auto it = g_physicalDeviceToInstanceMap.begin(); it != g_physicalDeviceToInstanceMap.end();) {
        if (it->second == tableKey) {
            it = g_physicalDeviceToInstanceMap.erase(it);
        } else {
            ++it;
        }
    }
    for (uint32_t i = 0; i < count; ++i) {
        g_physicalDeviceToInstanceMap[physicalDevices[i]] = tableKey;
    }
    return result;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator
) {
    PFN_vkDestroyInstance pfnDestroy = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
        auto instIt = g_instanceToDispatchTableMap.find(instance);
        if (instIt == g_instanceToDispatchTableMap.end()) {
            return;
        }

        const std::shared_ptr<WZHU_InstanceDispatchTable> table = instIt->second;
        WZHU_InstanceDispatchTable* dispatchTable = table.get();
        if (dispatchTable->pfn_vkDestroyInstance == nullptr) {
            return;
        }

        pfnDestroy = dispatchTable->pfn_vkDestroyInstance;
        const VkInstance canonical = dispatchTable->canonicalInstance;
        for (auto it = g_physicalDeviceToInstanceMap.begin(); it != g_physicalDeviceToInstanceMap.end();) {
            if (it->second == canonical) {
                it = g_physicalDeviceToInstanceMap.erase(it);
            } else {
                ++it;
            }
        }
        for (auto it = g_instanceToDispatchTableMap.begin(); it != g_instanceToDispatchTableMap.end();) {
            if (it->second == table) {
                it = g_instanceToDispatchTableMap.erase(it);
            } else {
                ++it;
            }
        }
    }

    pfnDestroy(instance, allocator);
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

    g_deviceToDispatchTableMap[*outDevice] = std::move(dispatchTable);

    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL IMPL_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator
) {
    auto deviceTableIt = g_deviceToDispatchTableMap.find(device);
    if (deviceTableIt == g_deviceToDispatchTableMap.end()) {
        return;
    }

    WZHU_DeviceDispatchTable* dispatchTable = deviceTableIt->second.get();
    if (dispatchTable->pfn_vkDestroyDevice == nullptr) {
        return;
    }

    for (auto iter = g_queueToDeviceMap.begin(); iter != g_queueToDeviceMap.end();) {
        if (iter->second == device) {
            iter = g_queueToDeviceMap.erase(iter);
        } else {
            ++iter;
        }
    }
    
    dispatchTable->pfn_vkDestroyDevice(device, allocator);
    g_deviceToDispatchTableMap.erase(device);
}


#ifdef HOOK_VULKAN_SURFACE_API
VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    VkSurfaceCapabilitiesKHR* capabilities
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceSurfaceCapabilitiesKHR)->pfn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        physicalDevice,
        surface,
        capabilities
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* formatCount,
    VkSurfaceFormatKHR* formats
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceSurfaceFormatsKHR)->pfn_vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        formatCount,
        formats
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkPhysicalDevice physicalDevice,
    VkSurfaceKHR surface,
    uint32_t* modeCount,
    VkPresentModeKHR* modes
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceSurfacePresentModesKHR)->pfn_vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        modeCount,
        modes
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceSurfaceSupportKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t queueFamilyIndex,
    VkSurfaceKHR surface,
    VkBool32* supported
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceSurfaceSupportKHR)->pfn_vkGetPhysicalDeviceSurfaceSupportKHR(
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
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPropertiesKHR* properties
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceDisplayPropertiesKHR)->pfn_vkGetPhysicalDeviceDisplayPropertiesKHR(
        physicalDevice,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t* propertyCount,
    VkDisplayPlanePropertiesKHR* properties
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetPhysicalDeviceDisplayPlanePropertiesKHR)->pfn_vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
        physicalDevice,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayModePropertiesKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    uint32_t* propertyCount,
    VkDisplayModePropertiesKHR* properties
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetDisplayModePropertiesKHR)->pfn_vkGetDisplayModePropertiesKHR(
        physicalDevice,
        display,
        propertyCount,
        properties
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneSupportedDisplaysKHR(
    VkPhysicalDevice physicalDevice,
    uint32_t planeIndex,
    uint32_t* displayCount,
    VkDisplayKHR* displays
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetDisplayPlaneSupportedDisplaysKHR)->pfn_vkGetDisplayPlaneSupportedDisplaysKHR(
        physicalDevice,
        planeIndex,
        displayCount,
        displays
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkGetDisplayPlaneCapabilitiesKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayModeKHR mode,
    uint32_t planeIndex,
    VkDisplayPlaneCapabilitiesKHR* capabilities
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkGetDisplayPlaneCapabilitiesKHR)->pfn_vkGetDisplayPlaneCapabilitiesKHR(
        physicalDevice,
        mode,
        planeIndex,
        capabilities
    );
}

VKAPI_ATTR VkResult VKAPI_CALL IMPL_vkCreateDisplayModeKHR(
    VkPhysicalDevice physicalDevice,
    VkDisplayKHR display,
    const VkDisplayModeCreateInfoKHR* createInfo,
    const VkAllocationCallbacks* allocator,
    VkDisplayModeKHR* outMode
) {
    const VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
    if (inst == VK_NULL_HANDLE) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    return GET_INSTANCE_DISPATCH_TABLE(inst, vkCreateDisplayModeKHR)->pfn_vkCreateDisplayModeKHR(
        physicalDevice,
        display,
        createInfo,
        allocator,
        outMode
    );
}
#endif // HOOK_VULKAN_SURFACE_API