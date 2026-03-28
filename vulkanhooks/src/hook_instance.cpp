// SPDX-License-Identifier: Apache-2.0

#include "wzhu_hooks.h"
#include "utils/wzhu_timing_statistics.h"
#include "layer_core/wzhu_layer_dispatch.h"
#include <chrono>
#include <memory>
#include <vector>

#define WZHU_INTERCEPT_INSTANCE_RESULT(InterceptName, MemberField, ApiId, FormalParams, ForwardArgs) \
    VKAPI_ATTR VkResult VKAPI_CALL Intercept##InterceptName FormalParams { \
        WZHU_InstanceExtrasTable* extrasTable = WZHU_instanceExtrasTableFor(instance); \
        if (extrasTable == nullptr || extrasTable->MemberField == nullptr) { \
            return VK_ERROR_INITIALIZATION_FAILED; \
        } \
        const auto timeStart = std::chrono::steady_clock::now(); \
        const VkResult result = extrasTable->MemberField ForwardArgs; \
        const auto timeEnd = std::chrono::steady_clock::now(); \
        WZHU_recordVulkanAPINanoseconds( \
            ApiId, \
            std::chrono::duration_cast<std::chrono::nanoseconds>(timeEnd - timeStart).count() \
        ); \
        return result; \
    }

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfaceCapabilitiesKHR,
    pfn_getSurfaceCaps,
    VulkanAPI_ID::GetPhysicalDeviceSurfaceCapabilitiesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkSurfaceKHR surface,
        VkSurfaceCapabilitiesKHR* capabilities
    ),
    (
        physical_device,
        surface,
        capabilities
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfaceFormatsKHR,
    pfn_getSurfaceFormats,
    VulkanAPI_ID::GetPhysicalDeviceSurfaceFormatsKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkSurfaceKHR surface,
        uint32_t* format_count,
        VkSurfaceFormatKHR* formats
    ),
    (
        physical_device,
        surface,
        format_count,
        formats
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfacePresentModesKHR,
    pfn_getSurfacePresentModes,
    VulkanAPI_ID::GetPhysicalDeviceSurfacePresentModesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkSurfaceKHR surface,
        uint32_t* mode_count,
        VkPresentModeKHR* modes
    ),
    (
        physical_device,
        surface,
        mode_count,
        modes
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceSurfaceSupportKHR,
    pfn_getSurfaceSupport,
    VulkanAPI_ID::GetPhysicalDeviceSurfaceSupportKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        uint32_t queue_family_index,
        VkSurfaceKHR surface,
        VkBool32* supported
    ),
    (
        physical_device,
        queue_family_index,
        surface,
        supported
    )
)

#if defined(VK_USE_PLATFORM_XCB_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateXcbSurfaceKHR,
    pfn_createXcbSurface,
    VulkanAPI_ID::CreateXcbSurfaceKHR,
    (
        VkInstance instance,
        const VkXcbSurfaceCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkSurfaceKHR* out_surface
    ),
    (
        instance,
        create_info,
        allocator,
        out_surface
    )
)
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateXlibSurfaceKHR,
    pfn_createXlibSurface,
    VulkanAPI_ID::CreateXlibSurfaceKHR,
    (
        VkInstance instance,
        const VkXlibSurfaceCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkSurfaceKHR* out_surface
    ),
    (
        instance,
        create_info,
        allocator,
        out_surface
    )
)
#endif

#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateWaylandSurfaceKHR,
    pfn_createWaylandSurface,
    VulkanAPI_ID::CreateWaylandSurfaceKHR,
    (
        VkInstance instance,
        const VkWaylandSurfaceCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkSurfaceKHR* out_surface
    ),
    (
        instance,
        create_info,
        allocator,
        out_surface
    )
)
#endif

#if defined(VK_USE_PLATFORM_WIN32_KHR)
WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateWin32SurfaceKHR,
    pfn_createWin32Surface,
    VulkanAPI_ID::CreateWin32SurfaceKHR,
    (
        VkInstance instance,
        const VkWin32SurfaceCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkSurfaceKHR* out_surface
    ),
    (
        instance,
        create_info,
        allocator,
        out_surface
    )
)
#endif

WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateDisplayPlaneSurfaceKHR,
    pfn_createDisplayPlaneSurface,
    VulkanAPI_ID::CreateDisplayPlaneSurfaceKHR,
    (
        VkInstance instance,
        const VkDisplaySurfaceCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkSurfaceKHR* out_surface
    ),
    (
        instance,
        create_info,
        allocator,
        out_surface
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceDisplayPropertiesKHR,
    pfn_getDisplayProps,
    VulkanAPI_ID::GetPhysicalDeviceDisplayPropertiesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        uint32_t* property_count,
        VkDisplayPropertiesKHR* properties
    ),
    (
        physical_device,
        property_count,
        properties
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetPhysicalDeviceDisplayPlanePropertiesKHR,
    pfn_getDisplayPlaneProps,
    VulkanAPI_ID::GetPhysicalDeviceDisplayPlanePropertiesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        uint32_t* property_count,
        VkDisplayPlanePropertiesKHR* properties
    ),
    (
        physical_device,
        property_count,
        properties
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetDisplayModePropertiesKHR,
    pfn_getDisplayModeProps,
    VulkanAPI_ID::GetDisplayModePropertiesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkDisplayKHR display,
        uint32_t* property_count,
        VkDisplayModePropertiesKHR* properties
    ),
    (
        physical_device,
        display,
        property_count,
        properties
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetDisplayPlaneSupportedDisplaysKHR,
    pfn_getDisplayPlaneSupportedDisplays,
    VulkanAPI_ID::GetDisplayPlaneSupportedDisplaysKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        uint32_t plane_index,
        uint32_t* display_count,
        VkDisplayKHR* displays
    ),
    (
        physical_device,
        plane_index,
        display_count,
        displays
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    GetDisplayPlaneCapabilitiesKHR,
    pfn_getDisplayPlaneCaps,
    VulkanAPI_ID::GetDisplayPlaneCapabilitiesKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkDisplayModeKHR mode,
        uint32_t plane_index,
        VkDisplayPlaneCapabilitiesKHR* capabilities
    ),
    (
        physical_device,
        mode,
        plane_index,
        capabilities
    )
)

WZHU_INTERCEPT_INSTANCE_RESULT(
    CreateDisplayModeKHR,
    pfn_createDisplayMode,
    VulkanAPI_ID::CreateDisplayModeKHR,
    (
        VkInstance instance,
        VkPhysicalDevice physical_device,
        VkDisplayKHR display,
        const VkDisplayModeCreateInfoKHR* create_info,
        const VkAllocationCallbacks* allocator,
        VkDisplayModeKHR* out_mode
    ),
    (
        physical_device,
        display,
        create_info,
        allocator,
        out_mode
    )
)

#undef WZHU_INTERCEPT_INSTANCE_RESULT

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateInstance(
    const VkInstanceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkInstance* out_instance
) {
    const VkLayerInstanceCreateInfo* layerInstanceCreateInfo =
        WZHU_findInstanceLayerCreateInfo(create_info);
    if (layerInstanceCreateInfo == nullptr || layerInstanceCreateInfo->function != VK_LAYER_LINK_INFO ||
        layerInstanceCreateInfo->u.pLayerInfo == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const PFN_vkGetInstanceProcAddr pfn_nextGetInstanceProcAddr =
        layerInstanceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    const PFN_vkCreateInstance pfn_nextCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(
        pfn_nextGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance")
    );
    if (pfn_nextCreateInstance == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    WZHU_startReportThreadOnce();

    const VkResult createResult = pfn_nextCreateInstance(create_info, allocator, out_instance);
    if (createResult != VK_SUCCESS || out_instance == nullptr || *out_instance == VK_NULL_HANDLE) {
        return createResult;
    }

    auto dispatchTable = std::make_unique<WZHU_InstanceDispatchTable>();
    dispatchTable->pfn_getInstanceProcAddr = pfn_nextGetInstanceProcAddr;
    dispatchTable->pfn_destroyInstance = reinterpret_cast<PFN_vkDestroyInstance>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkDestroyInstance")
    );
    dispatchTable->pfn_createDevice = reinterpret_cast<PFN_vkCreateDevice>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateDevice")
    );

    WZHU_storeInstanceDispatch(*out_instance, std::move(dispatchTable));

    auto extrasTable = std::make_unique<WZHU_InstanceExtrasTable>();
    extrasTable->pfn_getSurfaceCaps =
        reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")
        );
    extrasTable->pfn_getSurfaceFormats =
        reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceSurfaceFormatsKHR")
        );
    extrasTable->pfn_getSurfacePresentModes =
        reinterpret_cast<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceSurfacePresentModesKHR")
        );
    extrasTable->pfn_getSurfaceSupport =
        reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceSurfaceSupportKHR")
        );
#if defined(VK_USE_PLATFORM_XCB_KHR)
    extrasTable->pfn_createXcbSurface = reinterpret_cast<PFN_vkCreateXcbSurfaceKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateXcbSurfaceKHR")
    );
#endif
#if defined(VK_USE_PLATFORM_XLIB_KHR)
    extrasTable->pfn_createXlibSurface = reinterpret_cast<PFN_vkCreateXlibSurfaceKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateXlibSurfaceKHR")
    );
#endif
#if defined(VK_USE_PLATFORM_WAYLAND_KHR)
    extrasTable->pfn_createWaylandSurface = reinterpret_cast<PFN_vkCreateWaylandSurfaceKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateWaylandSurfaceKHR")
    );
#endif
#if defined(VK_USE_PLATFORM_WIN32_KHR)
    extrasTable->pfn_createWin32Surface = reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateWin32SurfaceKHR")
    );
#endif
    extrasTable->pfn_createDisplayPlaneSurface =
        reinterpret_cast<PFN_vkCreateDisplayPlaneSurfaceKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateDisplayPlaneSurfaceKHR")
        );
    extrasTable->pfn_getDisplayProps =
        reinterpret_cast<PFN_vkGetPhysicalDeviceDisplayPropertiesKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceDisplayPropertiesKHR")
        );
    extrasTable->pfn_getDisplayPlaneProps =
        reinterpret_cast<PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetPhysicalDeviceDisplayPlanePropertiesKHR")
        );
    extrasTable->pfn_getDisplayModeProps = reinterpret_cast<PFN_vkGetDisplayModePropertiesKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkGetDisplayModePropertiesKHR")
    );
    extrasTable->pfn_getDisplayPlaneSupportedDisplays =
        reinterpret_cast<PFN_vkGetDisplayPlaneSupportedDisplaysKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetDisplayPlaneSupportedDisplaysKHR")
        );
    extrasTable->pfn_getDisplayPlaneCaps =
        reinterpret_cast<PFN_vkGetDisplayPlaneCapabilitiesKHR>(
            pfn_nextGetInstanceProcAddr(*out_instance, "vkGetDisplayPlaneCapabilitiesKHR")
        );
    extrasTable->pfn_createDisplayMode = reinterpret_cast<PFN_vkCreateDisplayModeKHR>(
        pfn_nextGetInstanceProcAddr(*out_instance, "vkCreateDisplayModeKHR")
    );

    WZHU_storeInstanceExtras(*out_instance, std::move(extrasTable));

    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL InterceptDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* allocator
) {
    WZHU_InstanceDispatchTable* dispatchTable = WZHU_instanceDispatchTableFor(instance);
    if (dispatchTable == nullptr || dispatchTable->pfn_destroyInstance == nullptr) {
        return;
    }
    dispatchTable->pfn_destroyInstance(instance, allocator);
    WZHU_removeInstanceDispatch(instance);
    WZHU_removeInstanceExtras(instance);
}

VKAPI_ATTR VkResult VKAPI_CALL InterceptCreateDevice(
    VkPhysicalDevice physical_device,
    const VkDeviceCreateInfo* create_info,
    const VkAllocationCallbacks* allocator,
    VkDevice* out_device
) {
    const VkLayerDeviceCreateInfo* layerDeviceCreateInfo = WZHU_findDeviceLayerCreateInfo(create_info);
    if (layerDeviceCreateInfo == nullptr || layerDeviceCreateInfo->function != VK_LAYER_LINK_INFO ||
        layerDeviceCreateInfo->u.pLayerInfo == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    const PFN_vkGetInstanceProcAddr pfn_nextGetInstanceProcAddr =
        layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    const PFN_vkGetDeviceProcAddr pfn_nextGetDeviceProcAddr =
        layerDeviceCreateInfo->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    const PFN_vkCreateDevice pfn_nextCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(
        pfn_nextGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice")
    );
    if (pfn_nextCreateDevice == nullptr) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    VkDeviceCreateInfo patchedCreateInfo = *create_info;
    std::vector<const char*> extensions;
    extensions.reserve(patchedCreateInfo.enabledExtensionCount + 4u);
    for (uint32_t index = 0; index < patchedCreateInfo.enabledExtensionCount; ++index) {
        extensions.push_back(patchedCreateInfo.ppEnabledExtensionNames[index]);
    }
    const bool needCalibratedTimestamps =
        !WZHU_extensionNameEnabled(
            VK_KHR_CALIBRATED_TIMESTAMPS_EXTENSION_NAME,
            patchedCreateInfo.enabledExtensionCount,
            patchedCreateInfo.ppEnabledExtensionNames);
    if (needCalibratedTimestamps) {
        extensions.push_back(VK_KHR_CALIBRATED_TIMESTAMPS_EXTENSION_NAME);
    }
    patchedCreateInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    patchedCreateInfo.ppEnabledExtensionNames = extensions.data();

    WZHU_startReportThreadOnce();

    const VkResult createResult =
        pfn_nextCreateDevice(physical_device, &patchedCreateInfo, allocator, out_device);
    if (createResult != VK_SUCCESS || out_device == nullptr || *out_device == VK_NULL_HANDLE) {
        return createResult;
    }

    auto dispatchTable = std::make_unique<WZHU_DeviceDispatchTable>();
    dispatchTable->pfn_getDeviceProcAddr = pfn_nextGetDeviceProcAddr;
    dispatchTable->device = *out_device;
    dispatchTable->physicalDevice = physical_device;
    dispatchTable->pfn_destroyDevice = reinterpret_cast<PFN_vkDestroyDevice>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkDestroyDevice")
    );
    dispatchTable->pfn_getDeviceQueue = reinterpret_cast<PFN_vkGetDeviceQueue>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkGetDeviceQueue")
    );
    dispatchTable->pfn_getDeviceQueue2 = reinterpret_cast<PFN_vkGetDeviceQueue2>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkGetDeviceQueue2")
    );
    dispatchTable->pfn_createSwapchainKhr = reinterpret_cast<PFN_vkCreateSwapchainKHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkCreateSwapchainKHR")
    );
    dispatchTable->pfn_destroySwapchainKhr = reinterpret_cast<PFN_vkDestroySwapchainKHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkDestroySwapchainKHR")
    );
    dispatchTable->pfn_getSwapchainImagesKhr = reinterpret_cast<PFN_vkGetSwapchainImagesKHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkGetSwapchainImagesKHR")
    );
    dispatchTable->pfn_acquireNextImageKhr = reinterpret_cast<PFN_vkAcquireNextImageKHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkAcquireNextImageKHR")
    );
    dispatchTable->pfn_acquireNextImage2Khr = reinterpret_cast<PFN_vkAcquireNextImage2KHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkAcquireNextImage2KHR")
    );
    dispatchTable->pfn_queuePresentKhr = reinterpret_cast<PFN_vkQueuePresentKHR>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkQueuePresentKHR")
    );
    dispatchTable->pfn_queueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkQueueSubmit")
    );
    dispatchTable->pfn_queueSubmit2 = reinterpret_cast<PFN_vkQueueSubmit2>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkQueueSubmit2")
    );
    dispatchTable->pfn_queueBindSparse = reinterpret_cast<PFN_vkQueueBindSparse>(
        pfn_nextGetDeviceProcAddr(*out_device, "vkQueueBindSparse")
    );
    dispatchTable->pfn_getCalibratedTimestampsKhr =
        reinterpret_cast<PFN_vkGetCalibratedTimestampsKHR>(
            pfn_nextGetDeviceProcAddr(*out_device, "vkGetCalibratedTimestampsKHR")
        );

    dispatchTable->hasCalibratedTimestamps =
        (dispatchTable->pfn_getCalibratedTimestampsKhr != nullptr);

    WZHU_storeDeviceDispatch(*out_device, std::move(dispatchTable));

    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL InterceptDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* allocator
) {
    WZHU_DeviceDispatchTable* dispatchTable = WZHU_deviceDispatchTableFor(device);
    if (dispatchTable == nullptr || dispatchTable->pfn_destroyDevice == nullptr) {
        return;
    }
    WZHU_unregisterAllQueuesForDevice(device);
    dispatchTable->pfn_destroyDevice(device, allocator);
    WZHU_removeDeviceDispatch(device);
}
