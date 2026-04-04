#include "hook_instance.h"
#include "config.h"
#include "dump_hooked_api.h"
#include "layer_log.h"
#include "vulkan/vulkan_core.h"

#include <mutex>
#include <stdexcept>
#include <vector>

// While vkCreateInstance runs, the loader may call our vkGetInstanceProcAddr before we have a
// dispatch table entry for the new instance. IMPL_vkGetInstanceProcAddr then forwards those
// lookups to the next layer using the pointer from the layer chain (pfnNextGetInstanceProcAddr).
static std::mutex g_nextLayerVkGetInstanceProcAddrMutex;
static std::vector<PFN_vkGetInstanceProcAddr> g_nextLayerVkGetInstanceProcAddrStack;

static void pushNextLayerVkGetInstanceProcAddr(PFN_vkGetInstanceProcAddr next) {
    std::lock_guard<std::mutex> lock(g_nextLayerVkGetInstanceProcAddrMutex);
    g_nextLayerVkGetInstanceProcAddrStack.push_back(next);
}

static void popNextLayerVkGetInstanceProcAddr() {
    std::lock_guard<std::mutex> lock(g_nextLayerVkGetInstanceProcAddrMutex);
    g_nextLayerVkGetInstanceProcAddrStack.pop_back();
}

PFN_vkGetInstanceProcAddr WZHU_get_pfn_vkGetInstanceProcAddr_inFlight() {
    std::lock_guard<std::mutex> lock(g_nextLayerVkGetInstanceProcAddrMutex);
    if (g_nextLayerVkGetInstanceProcAddrStack.empty()) {
        return nullptr;
    }
    return g_nextLayerVkGetInstanceProcAddrStack.back();
}

VkInstance WZHU_instanceForPhysicalDevice(VkPhysicalDevice physicalDevice) {
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
        auto* layerInfo = reinterpret_cast<const VkLayerInstanceCreateInfo*>(chain);
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
        auto* layerInfo = reinterpret_cast<const VkLayerDeviceCreateInfo*>(chain);
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
        WZHU_LOG("Failed to find VkLayerInstanceCreateInfo from createInfo\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr = layerInstanceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkCreateInstance pfn_vkCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance"));
    if (pfn_vkCreateInstance == nullptr) {
        WZHU_LOG("Failed to call pfn_vkGetInstanceProcAddr\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    VkLayerInstanceCreateInfo* layerInstanceLink = const_cast<VkLayerInstanceCreateInfo*>(layerInstanceCreateInfo);
    if (layerInstanceLink->u.pLayerInfo != nullptr) {
        layerInstanceLink->u.pLayerInfo = layerInstanceLink->u.pLayerInfo->pNext;
    }

    pushNextLayerVkGetInstanceProcAddr(pfn_vkGetInstanceProcAddr);
    struct PopNextLayerVkGetInstanceProcAddrWhenLeaving {
        ~PopNextLayerVkGetInstanceProcAddrWhenLeaving() {
            popNextLayerVkGetInstanceProcAddr();
        }
    } popNextLayerVkGetInstanceProcAddrWhenLeaving;

    WZHU_CPUTimer cpuTimer;
    VkResult createResult = pfn_vkCreateInstance(createInfo, allocator, outInstance);
    if (createResult != VK_SUCCESS || outInstance == nullptr || *outInstance == VK_NULL_HANDLE) {
        WZHU_LOG("Failed to call pfn_vkCreateInstance\n");
        return createResult;
    }

    g_selectedInstance = *outInstance;
    g_pfn_vkGetInstanceProcAddr = pfn_vkGetInstanceProcAddr;
    WZHU_dump_vkCreateInstance(createInfo, allocator, outInstance, cpuTimer.endForUsec());

    // Register the instance before LOAD_INSTANCE_FUNC: pfn_vkGetInstanceProcAddr or the loader may
    // re-enter IMPL_vkGetInstanceProcAddr before the map exists; the stack above covers forwarding.
    auto dispatchTable = std::make_shared<WZHU_InstanceDispatchTable>();
    dispatchTable->pfn_vkGetInstanceProcAddr = pfn_vkGetInstanceProcAddr;
    WZHU_InstanceDispatchTable* dt = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
        g_instanceToDispatchTableMap[*outInstance] = dispatchTable;
        dt = g_instanceToDispatchTableMap[*outInstance].get();
    }

    dt->canonicalInstance = *outInstance;
    dt->pfn_vkDestroyInstance = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkDestroyInstance);
    dt->pfn_vkEnumeratePhysicalDevices = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkEnumeratePhysicalDevices);
    dt->pfn_vkCreateDevice = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateDevice);
    dt->pfn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
    dt->pfn_vkGetPhysicalDeviceSurfaceFormatsKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceSurfaceFormatsKHR);
    dt->pfn_vkGetPhysicalDeviceSurfacePresentModesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceSurfacePresentModesKHR);
    dt->pfn_vkGetPhysicalDeviceSurfaceSupportKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceSurfaceSupportKHR);
    dt->pfn_vkCreateDisplayPlaneSurfaceKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateDisplayPlaneSurfaceKHR);
    dt->pfn_vkGetPhysicalDeviceDisplayPropertiesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceDisplayPropertiesKHR);
    dt->pfn_vkGetPhysicalDeviceDisplayPlanePropertiesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetPhysicalDeviceDisplayPlanePropertiesKHR);
    dt->pfn_vkGetDisplayModePropertiesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetDisplayModePropertiesKHR);
    dt->pfn_vkGetDisplayPlaneSupportedDisplaysKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetDisplayPlaneSupportedDisplaysKHR);
    dt->pfn_vkGetDisplayPlaneCapabilitiesKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkGetDisplayPlaneCapabilitiesKHR);
    dt->pfn_vkCreateDisplayModeKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateDisplayModeKHR);
#if defined(VK_USE_PLATFORM_XCB_KHR)
    dt->pfn_vkCreateXcbSurfaceKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateXcbSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    dt->pfn_vkCreateXlibSurfaceKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateXlibSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    dt->pfn_vkCreateWaylandSurfaceKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateWaylandSurfaceKHR);
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    dt->pfn_vkCreateWin32SurfaceKHR = LOAD_INSTANCE_FUNC(pfn_vkGetInstanceProcAddr, *outInstance, vkCreateWin32SurfaceKHR);
#endif

    return VK_SUCCESS;
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

    WZHU_InstanceDispatchTable* instDispatch = GET_INSTANCE_DISPATCH_TABLE(tableKey, vkEnumeratePhysicalDevices);
    PFN_vkEnumeratePhysicalDevices pfn_vkEnumeratePhysicalDevices = instDispatch->pfn_vkEnumeratePhysicalDevices;
    VkResult result = pfn_vkEnumeratePhysicalDevices(instance, physicalDeviceCount, physicalDevices);
    if (result != VK_SUCCESS || physicalDeviceCount == nullptr || physicalDevices == nullptr) {
        return result;
    }

    std::lock_guard<std::mutex> lock(g_instanceDispatchTableMutex);
    for (auto it = g_physicalDeviceToInstanceMap.begin(); it != g_physicalDeviceToInstanceMap.end();) {
        if (it->second == tableKey) {
            it = g_physicalDeviceToInstanceMap.erase(it);
        } else {
            ++it;
        }
    }

    for (uint32_t i = 0; i < *physicalDeviceCount; ++i) {
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

        std::shared_ptr<WZHU_InstanceDispatchTable> table = instIt->second;
        WZHU_InstanceDispatchTable* dispatchTable = table.get();
        if (dispatchTable->pfn_vkDestroyInstance == nullptr) {
            return;
        }

        pfnDestroy = dispatchTable->pfn_vkDestroyInstance;
        VkInstance canonical = dispatchTable->canonicalInstance;
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
        WZHU_LOG("Failed to create logical device\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr = layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr = layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    if (pfn_vkGetDeviceProcAddr == nullptr) {
        WZHU_LOG("pfn_vkGetDeviceProcAddr is null\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    PFN_vkCreateDevice pfn_vkCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice"));
    if (pfn_vkCreateDevice == nullptr) {
        WZHU_LOG("Failed to call pfn_vkCreateDevice\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    VkLayerDeviceCreateInfo* layerDeviceLink = const_cast<VkLayerDeviceCreateInfo*>(layerDeviceCreateInfo);
    if (layerDeviceLink->u.pLayerInfo != nullptr) {
        layerDeviceLink->u.pLayerInfo = layerDeviceLink->u.pLayerInfo->pNext;
    }

    WZHU_CPUTimer cpuTimer;
    VkResult result = pfn_vkCreateDevice(physicalDevice, createInfo, allocator, outDevice);
    if (result != VK_SUCCESS || outDevice == nullptr || *outDevice == VK_NULL_HANDLE) {
        WZHU_LOG("Failed to create logical device\n");
        return result;
    }

    WZHU_dump_vkCreateDevice(physicalDevice, createInfo, allocator, outDevice, cpuTimer.endForUsec());

    PFN_vkGetDeviceProcAddr deviceProcLoader = pfn_vkGetDeviceProcAddr;

    auto dispatchTable = std::make_unique<WZHU_DeviceDispatchTable>();
    dispatchTable->pfn_vkGetDeviceProcAddr = deviceProcLoader;
    dispatchTable->device = *outDevice;
    dispatchTable->physicalDevice = physicalDevice;
    dispatchTable->pfn_vkDestroyDevice = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkDestroyDevice);
    dispatchTable->pfn_vkGetDeviceQueue = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkGetDeviceQueue);
    dispatchTable->pfn_vkGetDeviceQueue2 = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkGetDeviceQueue2);
    dispatchTable->pfn_vkCreateSwapchainKHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkCreateSwapchainKHR);
    dispatchTable->pfn_vkDestroySwapchainKHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkDestroySwapchainKHR);
    dispatchTable->pfn_vkGetSwapchainImagesKHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkGetSwapchainImagesKHR);
    dispatchTable->pfn_vkAcquireNextImageKHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkAcquireNextImageKHR);
    dispatchTable->pfn_vkAcquireNextImage2KHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkAcquireNextImage2KHR);
    dispatchTable->pfn_vkQueuePresentKHR = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkQueuePresentKHR);
    dispatchTable->pfn_vkQueueSubmit = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkQueueSubmit);
    dispatchTable->pfn_vkQueueSubmit2 = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkQueueSubmit2);
    dispatchTable->pfn_vkQueueBindSparse = LOAD_DEVICE_FUNC(deviceProcLoader, *outDevice, vkQueueBindSparse);

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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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
    VkInstance inst = WZHU_instanceForPhysicalDevice(physicalDevice);
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