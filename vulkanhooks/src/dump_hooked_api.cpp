#include "dump_hooked_api.h"
#include "layer_log.h"

#include <chrono>
#include <cstdio>
#include <ctime>

const char* WZHU_timestamp() {
    static char szbuf[256];
    const std::chrono::system_clock::time_point now = std::chrono::system_clock::now();
    const std::time_t t = std::chrono::system_clock::to_time_t(now);
    const std::chrono::milliseconds ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
    std::tm cal{};
#if defined(_WIN32)
    if (localtime_s(&cal, &t) != 0) {
        szbuf[0] = '\0';
        return szbuf;
    }
#else
    if (localtime_r(&t, &cal) == nullptr) {
        szbuf[0] = '\0';
        return szbuf;
    }
#endif
    snprintf(szbuf, sizeof(szbuf), "%04d-%02d-%02d %02d:%02d:%02d %03lld",
        cal.tm_year + 1900, cal.tm_mon + 1, cal.tm_mday,
        cal.tm_hour, cal.tm_min, cal.tm_sec,
        static_cast<long long>(ms.count())
    );

    return szbuf;
}

#ifdef DUMP_HOOKED_API
void WZHU_dump_vkCreateInstance(
    const VkInstanceCreateInfo* createInfo,
    const VkAllocationCallbacks* allocator,
    VkInstance* outInstance
) {
    WZHU_LogTree logTree;
    logTree.print("vkCreateInstance(\n");
    {
        logTree.push();
        logTree.print("[ IN] VkInstanceCreateInfo = {\n");
        {
            logTree.push();
            logTree.print("pNext = %s\n", createInfo->pNext ? "ADDR" : "NULL");
            logTree.print("VkInstanceCreateFlags = %d\n", createInfo->flags);
            if (createInfo->pApplicationInfo) {
                logTree.print("VkApplicationInfo = {\n", createInfo->flags);
                logTree.push();
                logTree.print("Application Name = %s\n", createInfo->pApplicationInfo->pApplicationName ? createInfo->pApplicationInfo->pApplicationName : "NULL");
                logTree.print("Application Version = %d\n", createInfo->pApplicationInfo->applicationVersion);
                logTree.print("Engine Name = %s\n", createInfo->pApplicationInfo->pEngineName ? createInfo->pApplicationInfo->pEngineName : "NULL");
                logTree.print("Engine Version = %d\n", createInfo->pApplicationInfo->engineVersion);
                logTree.print("API Version = %d.%d.%d\n", VK_VERSION_MAJOR(createInfo->pApplicationInfo->apiVersion), VK_VERSION_MINOR(createInfo->pApplicationInfo->apiVersion), VK_VERSION_PATCH(createInfo->pApplicationInfo->apiVersion));
                logTree.pop();
            } else {
                logTree.print("VkApplicationInfo = NULL\n");
            }
            logTree.print("}\n");
            logTree.printStringList("Enabled Layer Names", createInfo->ppEnabledLayerNames, createInfo->enabledLayerCount);
            logTree.printStringList("Enabled Extension Names", createInfo->ppEnabledExtensionNames, createInfo->enabledExtensionCount);
            logTree.pop();
        }
        logTree.print("}\n");
        logTree.print("[ IN] VkAllocationCallbacks = %s\n", allocator ? "ADDR" : "NULL");
        logTree.print("[OUT] VkInstance = %p\n", *outInstance);
        logTree.pop();
    }
    logTree.print(") -> VK_SUCCESS @ [%s]\n", WZHU_timestamp());
}

void WZHU_dump_vkCreateDevice(
    VkPhysicalDevice physicalDevice, 
    const VkDeviceCreateInfo* pCreateInfo, 
    const VkAllocationCallbacks* pAllocator, 
    VkDevice* pDevice
) {
    
}
#endif // DUMP_HOOKED_API