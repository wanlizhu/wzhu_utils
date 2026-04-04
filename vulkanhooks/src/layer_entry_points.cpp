#include "hook_dispatch.h"

static const VkLayerProperties gkInstanceLayerProperties = {
    "VK_LAYER_WZHU_profiling",
    VK_MAKE_API_VERSION(0, 1, 3, 280),
    1,
    "WZHU profiling layer (swapchain/display/submit timing)",
};

// Entry points exported for the Vulkan loader to discover, load, and dispatch this layer.
extern "C" {
    WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(
        VkNegotiateLayerInterface* versionStruct
    ) {
        if (versionStruct == nullptr || versionStruct->sType != LAYER_NEGOTIATE_INTERFACE_STRUCT) {
            return VK_ERROR_INITIALIZATION_FAILED;
        }
        if (versionStruct->loaderLayerInterfaceVersion < MIN_SUPPORTED_LOADER_LAYER_INTERFACE_VERSION) {
            return VK_ERROR_INITIALIZATION_FAILED;
        }
        if (versionStruct->loaderLayerInterfaceVersion > CURRENT_LOADER_LAYER_INTERFACE_VERSION) {
            versionStruct->loaderLayerInterfaceVersion = CURRENT_LOADER_LAYER_INTERFACE_VERSION;
        }
        versionStruct->pfnGetInstanceProcAddr = IMPL_vkGetInstanceProcAddr;
        versionStruct->pfnGetDeviceProcAddr = IMPL_vkGetDeviceProcAddr;
        versionStruct->pfnGetPhysicalDeviceProcAddr = IMPL_vkGetPhysicalDeviceProcAddr;
        return VK_SUCCESS;
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(
        VkInstance instance,
        const char* name
    ) {
        return IMPL_vkGetInstanceProcAddr(instance, name);
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(
        VkDevice device,
        const char* name
    ) {
        return IMPL_vkGetDeviceProcAddr(device, name);
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceLayerProperties(
        uint32_t* propertyCount,
        VkLayerProperties* properties
    ) {
        if (propertyCount == nullptr) {
            return VK_INCOMPLETE;
        }
        if (properties == nullptr) {
            *propertyCount = 1;
            return VK_SUCCESS;
        }
        if (*propertyCount < 1) {
            *propertyCount = 1;
            return VK_INCOMPLETE;
        }
        *propertyCount = 1;
        properties[0] = gkInstanceLayerProperties;
        return VK_SUCCESS;
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceExtensionProperties(
        const char* layerName,
        uint32_t* propertyCount,
        VkExtensionProperties* properties
    ) {
        UNUSED_VARS(properties);
        if (layerName != nullptr && std::strcmp(layerName, "VK_LAYER_WZHU_profiling") != 0) {
            return VK_ERROR_LAYER_NOT_PRESENT;
        }
        if (propertyCount != nullptr) {
            *propertyCount = 0;
        }
        return VK_SUCCESS;
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceLayerProperties(
        VkPhysicalDevice physicalDevice,
        uint32_t* propertyCount,
        VkLayerProperties* properties
    ) {
        UNUSED_VARS(physicalDevice);
        return vkEnumerateInstanceLayerProperties(propertyCount, properties);
    }
    
    WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceExtensionProperties(
        VkPhysicalDevice physicalDevice,
        const char* layerName,
        uint32_t* propertyCount,
        VkExtensionProperties* properties
    ) {
        UNUSED_VARS(physicalDevice, properties);
        if (layerName != nullptr && std::strcmp(layerName, "VK_LAYER_WZHU_profiling") != 0) {
            return VK_ERROR_LAYER_NOT_PRESENT;
        }
        if (propertyCount != nullptr) {
            *propertyCount = 0;
        }
        return VK_SUCCESS;
    }
} // extern "C"
