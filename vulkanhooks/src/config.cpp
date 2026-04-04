#include "config.h"

std::mutex g_instanceDispatchTableMutex;
std::unordered_map<VkInstance, std::shared_ptr<WZHU_InstanceDispatchTable>> g_instanceToDispatchTableMap;
std::unordered_map<VkPhysicalDevice, VkInstance> g_physicalDeviceToInstanceMap;
std::unordered_map<VkDevice, std::unique_ptr<WZHU_DeviceDispatchTable>> g_deviceToDispatchTableMap;
std::unordered_map<VkQueue, VkDevice> g_queueToDeviceMap;
