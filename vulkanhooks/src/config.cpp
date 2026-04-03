#include "config.h"

std::unordered_map<VkInstance, std::unique_ptr<WZHU_InstanceDispatchTable>> g_instanceDispatchTableMap;
std::unordered_map<VkDevice, std::unique_ptr<WZHU_DeviceDispatchTable>> g_deviceDispatchTableMap;
std::unordered_map<VkQueue, VkDevice> g_queueDeviceMap;
