#pragma once

#if defined(_WIN32)
#define WZHU_LAYER_EXPORT __declspec(dllexport)
#else
#define WZHU_LAYER_EXPORT __attribute__((visibility("default")))
#endif
