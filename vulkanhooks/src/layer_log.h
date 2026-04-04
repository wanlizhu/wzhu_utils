#pragma once
#include "config.h"

const char* WZHU_VkResult(VkResult result);

struct WZHU_LogTree {
    WZHU_LogTree();
    WZHU_LogTree(const WZHU_LogTree&) = delete;
    WZHU_LogTree& operator=(const WZHU_LogTree&) = delete;
    WZHU_LogTree(WZHU_LogTree&&) = delete;
    WZHU_LogTree& operator=(WZHU_LogTree&&) = delete;

    void push();
    void pop();
    void print(const char* fmt, ...);
    void printStringList(const char* name, const char* const* strs, uint32_t count);

private:
    int m_indent = 0;
};
