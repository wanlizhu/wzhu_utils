#pragma once
// Registry of next-layer dispatch tables (instance, device, instance-extras) and VkQueue → VkDevice
// associations for queue interceptors.

#include "layer_core/wzhu_dispatch_types.h"
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <memory>
#include <shared_mutex>
#include <unordered_map>

WZHU_InstanceDispatchTable* WZHU_instanceDispatchTableFor(VkInstance instance_handle);
WZHU_DeviceDispatchTable* WZHU_deviceDispatchTableFor(VkDevice device_handle);
WZHU_InstanceExtrasTable* WZHU_instanceExtrasTableFor(VkInstance instance_handle);
void WZHU_registerQueueHandle(VkQueue queue_handle, VkDevice device_handle);
void WZHU_unregisterAllQueuesForDevice(VkDevice device_handle);
VkDevice WZHU_deviceHandleForQueue(VkQueue queue_handle);
const VkLayerInstanceCreateInfo* WZHU_findInstanceLayerCreateInfo(
    const VkInstanceCreateInfo* create_info
);
const VkLayerDeviceCreateInfo* WZHU_findDeviceLayerCreateInfo(
    const VkDeviceCreateInfo* create_info
);
bool WZHU_extensionNameEnabled(
    const char* extension_name,
    uint32_t enabled_count,
    const char* const* enabled_names
);
void WZHU_storeInstanceDispatch(
    VkInstance instance_handle,
    std::unique_ptr<WZHU_InstanceDispatchTable> dispatch_table
);
void WZHU_removeInstanceDispatch(VkInstance instance_handle);
void WZHU_storeInstanceExtras(
    VkInstance instance_handle,
    std::unique_ptr<WZHU_InstanceExtrasTable> extras_table
);
void WZHU_removeInstanceExtras(VkInstance instance_handle);
void WZHU_storeDeviceDispatch(
    VkDevice device_handle,
    std::unique_ptr<WZHU_DeviceDispatchTable> dispatch_table
);
void WZHU_removeDeviceDispatch(VkDevice device_handle);
