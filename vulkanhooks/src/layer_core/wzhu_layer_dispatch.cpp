// SPDX-License-Identifier: Apache-2.0
// Implementation: layer_core/wzhu_layer_dispatch.h

#include "layer_core/wzhu_layer_dispatch.h"
#include <cstring>

struct GR {
    std::shared_mutex instance_mutex{};
    std::unordered_map<VkInstance, std::unique_ptr<WZHU_InstanceDispatchTable>> instance_dispatch_by_handle{};
    std::unordered_map<VkInstance, std::unique_ptr<WZHU_InstanceExtrasTable>> instance_extras_by_handle{};

    std::shared_mutex device_mutex{};
    std::unordered_map<VkDevice, std::unique_ptr<WZHU_DeviceDispatchTable>> device_dispatch_by_handle{};

    std::shared_mutex queue_mutex{};
    std::unordered_map<VkQueue, VkDevice> device_handle_by_queue{};
};

static GR gr;

WZHU_InstanceDispatchTable* WZHU_instanceDispatchTableFor(VkInstance instance_handle) {
    std::shared_lock<std::shared_mutex> lock(gr.instance_mutex);
    const auto found = gr.instance_dispatch_by_handle.find(instance_handle);
    if (found == gr.instance_dispatch_by_handle.end()) {
        return nullptr;
    }
    return found->second.get();
}

WZHU_DeviceDispatchTable* WZHU_deviceDispatchTableFor(VkDevice device_handle) {
    std::shared_lock<std::shared_mutex> lock(gr.device_mutex);
    const auto found = gr.device_dispatch_by_handle.find(device_handle);
    if (found == gr.device_dispatch_by_handle.end()) {
        return nullptr;
    }
    return found->second.get();
}

WZHU_InstanceExtrasTable* WZHU_instanceExtrasTableFor(VkInstance instance_handle) {
    std::shared_lock<std::shared_mutex> lock(gr.instance_mutex);
    const auto found = gr.instance_extras_by_handle.find(instance_handle);
    if (found == gr.instance_extras_by_handle.end()) {
        return nullptr;
    }
    return found->second.get();
}

void WZHU_registerQueueHandle(VkQueue queue_handle, VkDevice device_handle) {
    if (queue_handle == VK_NULL_HANDLE || device_handle == VK_NULL_HANDLE) {
        return;
    }
    std::unique_lock<std::shared_mutex> lock(gr.queue_mutex);
    gr.device_handle_by_queue[queue_handle] = device_handle;
}

void WZHU_unregisterAllQueuesForDevice(VkDevice device_handle) {
    if (device_handle == VK_NULL_HANDLE) {
        return;
    }
    std::unique_lock<std::shared_mutex> lock(gr.queue_mutex);
    for (auto iterator = gr.device_handle_by_queue.begin();
         iterator != gr.device_handle_by_queue.end();) {
        if (iterator->second == device_handle) {
            iterator = gr.device_handle_by_queue.erase(iterator);
        } else {
            ++iterator;
        }
    }
}

VkDevice WZHU_deviceHandleForQueue(VkQueue queue_handle) {
    std::shared_lock<std::shared_mutex> lock(gr.queue_mutex);
    const auto found = gr.device_handle_by_queue.find(queue_handle);
    if (found == gr.device_handle_by_queue.end()) {
        return VK_NULL_HANDLE;
    }
    return found->second;
}

const VkLayerInstanceCreateInfo* WZHU_findInstanceLayerCreateInfo(
    const VkInstanceCreateInfo* create_info
) {
    for (const VkBaseInStructure* chain = reinterpret_cast<const VkBaseInStructure*>(create_info->pNext);
         chain != nullptr;
         chain = reinterpret_cast<const VkBaseInStructure*>(chain->pNext)) {
        if (chain->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO) {
            return reinterpret_cast<const VkLayerInstanceCreateInfo*>(chain);
        }
    }
    return nullptr;
}

const VkLayerDeviceCreateInfo* WZHU_findDeviceLayerCreateInfo(
    const VkDeviceCreateInfo* create_info
) {
    for (const VkBaseInStructure* chain = reinterpret_cast<const VkBaseInStructure*>(create_info->pNext);
         chain != nullptr;
         chain = reinterpret_cast<const VkBaseInStructure*>(chain->pNext)) {
        if (chain->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO) {
            return reinterpret_cast<const VkLayerDeviceCreateInfo*>(chain);
        }
    }
    return nullptr;
}

bool WZHU_extensionNameEnabled(
    const char* extension_name,
    uint32_t enabled_count,
    const char* const* enabled_names
) {
    for (uint32_t index = 0; index < enabled_count; ++index) {
        if (enabled_names[index] != nullptr && std::strcmp(enabled_names[index], extension_name) == 0) {
            return true;
        }
    }
    return false;
}

void WZHU_storeInstanceDispatch(
    VkInstance instance_handle,
    std::unique_ptr<WZHU_InstanceDispatchTable> dispatch_table
) {
    std::unique_lock<std::shared_mutex> lock(gr.instance_mutex);
    gr.instance_dispatch_by_handle[instance_handle] = std::move(dispatch_table);
}

void WZHU_removeInstanceDispatch(VkInstance instance_handle) {
    std::unique_lock<std::shared_mutex> lock(gr.instance_mutex);
    gr.instance_dispatch_by_handle.erase(instance_handle);
}

void WZHU_storeInstanceExtras(
    VkInstance instance_handle,
    std::unique_ptr<WZHU_InstanceExtrasTable> extras_table
) {
    std::unique_lock<std::shared_mutex> lock(gr.instance_mutex);
    gr.instance_extras_by_handle[instance_handle] = std::move(extras_table);
}

void WZHU_removeInstanceExtras(VkInstance instance_handle) {
    std::unique_lock<std::shared_mutex> lock(gr.instance_mutex);
    gr.instance_extras_by_handle.erase(instance_handle);
}

void WZHU_storeDeviceDispatch(
    VkDevice device_handle,
    std::unique_ptr<WZHU_DeviceDispatchTable> dispatch_table
) {
    std::unique_lock<std::shared_mutex> lock(gr.device_mutex);
    gr.device_dispatch_by_handle[device_handle] = std::move(dispatch_table);
}

void WZHU_removeDeviceDispatch(VkDevice device_handle) {
    std::unique_lock<std::shared_mutex> lock(gr.device_mutex);
    gr.device_dispatch_by_handle.erase(device_handle);
}
