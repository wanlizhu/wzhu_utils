// SPDX-License-Identifier: Apache-2.0
// Vulkan loader entry points exported from this shared library: layer negotiation, layer/enumeration
// queries, and trampoline vkGetInstanceProcAddr / vkGetDeviceProcAddr symbols.

#include "wzhu_hooks.h"
#include "layer_core/wzhu_layer.h"
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <cstring>

struct GR {
    const VkLayerProperties instance_layer_description = {
        "VK_LAYER_WZHU_profiling",
        VK_MAKE_API_VERSION(0, 1, 3, 280),
        1,
        "WZHU profiling layer (swapchain/display/submit timing)",
    };
};

static GR gr;

extern "C" {
WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(
    VkNegotiateLayerInterface* version_struct) {
    if (version_struct == nullptr || version_struct->sType != LAYER_NEGOTIATE_INTERFACE_STRUCT) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    if (version_struct->loaderLayerInterfaceVersion < MIN_SUPPORTED_LOADER_LAYER_INTERFACE_VERSION) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    if (version_struct->loaderLayerInterfaceVersion > CURRENT_LOADER_LAYER_INTERFACE_VERSION) {
        version_struct->loaderLayerInterfaceVersion = CURRENT_LOADER_LAYER_INTERFACE_VERSION;
    }
    version_struct->pfnGetInstanceProcAddr = IMPL_vkGetInstanceProcAddr;
    version_struct->pfnGetDeviceProcAddr = IMPL_vkGetDeviceProcAddr;
    version_struct->pfnGetPhysicalDeviceProcAddr = IMPL_vkGetPhysicalDeviceProcAddr;
    return VK_SUCCESS;
}
WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(
    VkInstance instance,
    const char* name) {
    return IMPL_vkGetInstanceProcAddr(instance, name);
}
WZHU_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(
    VkDevice device,
    const char* name) {
    return IMPL_vkGetDeviceProcAddr(device, name);
}
WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceLayerProperties(
    uint32_t* property_count,
    VkLayerProperties* properties) {
    if (property_count == nullptr) {
        return VK_INCOMPLETE;
    }
    if (properties == nullptr) {
        *property_count = 1;
        return VK_SUCCESS;
    }
    if (*property_count < 1) {
        *property_count = 1;
        return VK_INCOMPLETE;
    }
    *property_count = 1;
    properties[0] = gr.instance_layer_description;
    return VK_SUCCESS;
}
WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceExtensionProperties(
    const char* layer_name,
    uint32_t* property_count,
    VkExtensionProperties* properties) {
    (void)properties;
    if (layer_name != nullptr && std::strcmp(layer_name, "VK_LAYER_WZHU_profiling") != 0) {
        return VK_ERROR_LAYER_NOT_PRESENT;
    }
    if (property_count != nullptr) {
        *property_count = 0;
    }
    return VK_SUCCESS;
}
WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceLayerProperties(
    VkPhysicalDevice physical_device,
    uint32_t* property_count,
    VkLayerProperties* properties) {
    (void)physical_device;
    return vkEnumerateInstanceLayerProperties(property_count, properties);
}
WZHU_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceExtensionProperties(
    VkPhysicalDevice physical_device,
    const char* layer_name,
    uint32_t* property_count,
    VkExtensionProperties* properties) {
    (void)physical_device;
    return vkEnumerateInstanceExtensionProperties(layer_name, property_count, properties);
}
} // extern "C"
