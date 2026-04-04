#pragma once
#include "config.h"
#include <chrono>
#include <vulkan/vulkan_core.h>

const char* WZHU_VkResult(VkResult result);
const char* WZHU_VkQueueFlags(VkQueueFlags flags);

struct WZHU_LogTree {
    WZHU_LogTree();
    WZHU_LogTree(const WZHU_LogTree&) = delete;
    WZHU_LogTree& operator=(const WZHU_LogTree&) = delete;
    WZHU_LogTree(WZHU_LogTree&&) = delete;
    WZHU_LogTree& operator=(WZHU_LogTree&&) = delete;

    void push();
    void pop();
    void print(const char* fmt, ...);
    void printStringList(
        const char* name, 
        const char* const* strs, 
        uint32_t count,
        bool oneline
    );
    void printPhysicalDeviceFeatures(
        const char* name,
        const VkPhysicalDeviceFeatures* features,
        bool oneline 
    );

private:
    int m_indent = 0;
};

struct WZHU_CPUTimer {
    WZHU_CPUTimer();
    WZHU_CPUTimer(const WZHU_CPUTimer&) = delete;
    WZHU_CPUTimer& operator=(const WZHU_CPUTimer&) = delete;
    WZHU_CPUTimer(WZHU_CPUTimer&&) = delete;
    WZHU_CPUTimer& operator=(WZHU_CPUTimer&&) = delete;

    uint32_t endForMsec();
    uint32_t endForUsec();
    uint32_t endForNsec();

private:
    std::chrono::high_resolution_clock::time_point m_start;
};