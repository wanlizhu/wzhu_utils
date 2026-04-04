#include "layer_log.h"
#include <chrono>
#include <cstddef>
#include <cstring>
#include <ratio>
#include <string>
#include <vulkan/vulkan_core.h>

static constexpr std::size_t gk_physicalDeviceFeatureNamesCount = sizeof(VkPhysicalDeviceFeatures) / sizeof(VkBool32);
static const char* const gk_physicalDeviceFeatureNames[gk_physicalDeviceFeatureNamesCount] = {
    "robustBufferAccess",
    "fullDrawIndexUint32",
    "imageCubeArray",
    "independentBlend",
    "geometryShader",
    "tessellationShader",
    "sampleRateShading",
    "dualSrcBlend",
    "logicOp",
    "multiDrawIndirect",
    "drawIndirectFirstInstance",
    "depthClamp",
    "depthBiasClamp",
    "fillModeNonSolid",
    "depthBounds",
    "wideLines",
    "largePoints",
    "alphaToOne",
    "multiViewport",
    "samplerAnisotropy",
    "textureCompressionETC2",
    "textureCompressionASTC_LDR",
    "textureCompressionBC",
    "occlusionQueryPrecise",
    "pipelineStatisticsQuery",
    "vertexPipelineStoresAndAtomics",
    "fragmentStoresAndAtomics",
    "shaderTessellationAndGeometryPointSize",
    "shaderImageGatherExtended",
    "shaderStorageImageExtendedFormats",
    "shaderStorageImageMultisample",
    "shaderStorageImageReadWithoutFormat",
    "shaderStorageImageWriteWithoutFormat",
    "shaderUniformBufferArrayDynamicIndexing",
    "shaderSampledImageArrayDynamicIndexing",
    "shaderStorageBufferArrayDynamicIndexing",
    "shaderStorageImageArrayDynamicIndexing",
    "shaderClipDistance",
    "shaderCullDistance",
    "shaderFloat64",
    "shaderInt64",
    "shaderInt16",
    "shaderResourceResidency",
    "shaderResourceMinLod",
    "sparseBinding",
    "sparseResidencyBuffer",
    "sparseResidencyImage2D",
    "sparseResidencyImage3D",
    "sparseResidency2Samples",
    "sparseResidency4Samples",
    "sparseResidency8Samples",
    "sparseResidency16Samples",
    "sparseResidencyAliased",
    "variableMultisampleRate",
    "inheritedQueries",
};
static_assert(sizeof(gk_physicalDeviceFeatureNames) / sizeof(gk_physicalDeviceFeatureNames[0]) == gk_physicalDeviceFeatureNamesCount, "gk_physicalDeviceFeatureNames must match VkPhysicalDeviceFeatures VkBool32 count");

const char* WZHU_VkResult(VkResult result) {
    switch (result) {
        case VK_SUCCESS: return "VK_SUCCESS";
        case VK_NOT_READY: return "VK_NOT_READY";
        case VK_TIMEOUT: return "VK_TIMEOUT";
        case VK_EVENT_SET: return "VK_EVENT_SET";
        case VK_EVENT_RESET: return "VK_EVENT_RESET";
        case VK_INCOMPLETE: return "VK_INCOMPLETE";
        case VK_ERROR_OUT_OF_HOST_MEMORY: return "VK_ERROR_OUT_OF_HOST_MEMORY";
        case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
        case VK_ERROR_INITIALIZATION_FAILED: return "VK_ERROR_INITIALIZATION_FAILED";
        case VK_ERROR_DEVICE_LOST: return "VK_ERROR_DEVICE_LOST";
        case VK_ERROR_MEMORY_MAP_FAILED: return "VK_ERROR_MEMORY_MAP_FAILED";
        case VK_ERROR_LAYER_NOT_PRESENT: return "VK_ERROR_LAYER_NOT_PRESENT";
        case VK_ERROR_EXTENSION_NOT_PRESENT: return "VK_ERROR_EXTENSION_NOT_PRESENT";
        case VK_ERROR_FEATURE_NOT_PRESENT: return "VK_ERROR_FEATURE_NOT_PRESENT";
        case VK_ERROR_INCOMPATIBLE_DRIVER: return "VK_ERROR_INCOMPATIBLE_DRIVER";
        case VK_ERROR_TOO_MANY_OBJECTS: return "VK_ERROR_TOO_MANY_OBJECTS";
        case VK_ERROR_FORMAT_NOT_SUPPORTED: return "VK_ERROR_FORMAT_NOT_SUPPORTED";
        case VK_ERROR_FRAGMENTED_POOL: return "VK_ERROR_FRAGMENTED_POOL";
#if defined(VK_API_VERSION_1_1)
        case VK_ERROR_OUT_OF_POOL_MEMORY: return "VK_ERROR_OUT_OF_POOL_MEMORY";
        case VK_ERROR_INVALID_EXTERNAL_HANDLE: return "VK_ERROR_INVALID_EXTERNAL_HANDLE";
#endif
#if defined(VK_API_VERSION_1_2)
        case VK_ERROR_UNKNOWN: return "VK_ERROR_UNKNOWN";
        case VK_ERROR_FRAGMENTATION: return "VK_ERROR_FRAGMENTATION";
        case VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS: return "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS";
#endif
#if !defined(VK_API_VERSION_1_2)
        case VK_ERROR_FRAGMENTATION_EXT: return "VK_ERROR_FRAGMENTATION_EXT";
        case VK_ERROR_INVALID_DEVICE_ADDRESS_EXT: return "VK_ERROR_INVALID_DEVICE_ADDRESS_EXT";
#endif
#if defined(VK_API_VERSION_1_3)
        case VK_PIPELINE_COMPILE_REQUIRED: return "VK_PIPELINE_COMPILE_REQUIRED";
#endif
#if defined(VK_API_VERSION_1_4)
        case VK_ERROR_NOT_PERMITTED: return "VK_ERROR_NOT_PERMITTED";
#endif
#if defined(VK_KHR_pipeline_binary)
        case VK_PIPELINE_BINARY_MISSING_KHR: return "VK_PIPELINE_BINARY_MISSING_KHR";
        case VK_ERROR_NOT_ENOUGH_SPACE_KHR: return "VK_ERROR_NOT_ENOUGH_SPACE_KHR";
#endif
#if !defined(VK_API_VERSION_1_4)
        case VK_ERROR_NOT_PERMITTED_EXT: return "VK_ERROR_NOT_PERMITTED_EXT";
#endif
#if defined(VK_KHR_surface)
        case VK_ERROR_SURFACE_LOST_KHR: return "VK_ERROR_SURFACE_LOST_KHR";
        case VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
#endif
#if defined(VK_KHR_swapchain)
        case VK_SUBOPTIMAL_KHR: return "VK_SUBOPTIMAL_KHR";
        case VK_ERROR_OUT_OF_DATE_KHR: return "VK_ERROR_OUT_OF_DATE_KHR";
#endif
#if defined(VK_KHR_display_swapchain)
        case VK_ERROR_INCOMPATIBLE_DISPLAY_KHR: return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR";
#endif
#if defined(VK_EXT_debug_report)
        case VK_ERROR_VALIDATION_FAILED_EXT: return "VK_ERROR_VALIDATION_FAILED_EXT";
#endif
#if defined(VK_NV_glsl_shader)
        case VK_ERROR_INVALID_SHADER_NV: return "VK_ERROR_INVALID_SHADER_NV";
#endif
#if defined(VK_KHR_video_queue)
        case VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR: return "VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR";
        case VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR: return "VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR";
        case VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR: return "VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR";
        case VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR: return "VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR";
        case VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR: return "VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR";
        case VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR: return "VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR";
#endif
#if defined(VK_EXT_image_drm_format_modifier)
        case VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT: return "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT";
#endif
#if defined(VK_EXT_full_screen_exclusive) || defined(VK_EXT_FULL_SCREEN_EXCLUSIVE_SPEC_VERSION) || (VK_HEADER_VERSION >= 108)
        case VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT: return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT";
#endif
#if defined(VK_KHR_deferred_host_operations)
        case VK_THREAD_IDLE_KHR: return "VK_THREAD_IDLE_KHR";
        case VK_THREAD_DONE_KHR: return "VK_THREAD_DONE_KHR";
        case VK_OPERATION_DEFERRED_KHR: return "VK_OPERATION_DEFERRED_KHR";
        case VK_OPERATION_NOT_DEFERRED_KHR: return "VK_OPERATION_NOT_DEFERRED_KHR";
#endif
#if defined(VK_KHR_video_encode_queue)
        case VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR: return "VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR";
#endif
#if defined(VK_EXT_image_compression_control)
        case VK_ERROR_COMPRESSION_EXHAUSTED_EXT: return "VK_ERROR_COMPRESSION_EXHAUSTED_EXT";
#endif
#if defined(VK_EXT_shader_object)
        case VK_INCOMPATIBLE_SHADER_BINARY_EXT: return "VK_INCOMPATIBLE_SHADER_BINARY_EXT";
#endif
        case VK_RESULT_MAX_ENUM: return "VK_RESULT_MAX_ENUM";
        default: {
            static thread_local char buf[48];
            std::snprintf(buf, sizeof(buf), "VkResult(%d)", static_cast<int>(result));
            return buf;
        }
    }
}

const char* WZHU_VkQueueFlags(VkQueueFlags flags) {
    static char szbuf[256];
    memset(szbuf, 0, sizeof(szbuf));

    std::string tmp = "";
    if (flags & VK_QUEUE_GRAPHICS_BIT) { tmp += (tmp.empty() ? "GFX" : "|GFX"); }
    if (flags & VK_QUEUE_COMPUTE_BIT) { tmp += (tmp.empty() ? "COMP" : "|COMP"); }
    if (flags & VK_QUEUE_TRANSFER_BIT) { tmp += (tmp.empty() ? "TRANS" : "|TRANS"); }
    if (flags & VK_QUEUE_SPARSE_BINDING_BIT) { tmp += (tmp.empty() ? "SPARSE" : "|SPARSE"); }
#if defined(VK_API_VERSION_1_1)
    if (flags & VK_QUEUE_PROTECTED_BIT) { tmp += (tmp.empty() ? "PROTECTED" : "|PROTECTED"); }
#endif
#if defined(VK_KHR_video_queue)
    if (flags & VK_QUEUE_VIDEO_DECODE_BIT_KHR) { tmp += (tmp.empty() ? "VDEC" : "|VDEC"); }
#endif
#if defined(VK_KHR_video_encode_queue)
    if (flags & VK_QUEUE_VIDEO_ENCODE_BIT_KHR) { tmp += (tmp.empty() ? "VENC" : "|VENC"); }
#endif

    memcpy(szbuf, tmp.c_str(), tmp.size());

    return szbuf;
}

WZHU_LogTree::WZHU_LogTree() {}

void WZHU_LogTree::push() {
    m_indent += 4;
}

void WZHU_LogTree::pop() {
    if (m_indent >= 4) {
        m_indent -= 4;
    }
}

void WZHU_LogTree::print(const char* fmt, ...) {
    if (fmt == nullptr) {
        return;
    }
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[wzhu] ");
    for (int i = 0; i < m_indent; ++i) {
        fputc(' ', stderr);
    }
    vfprintf(stderr, fmt, args);
    va_end(args);
}

void WZHU_LogTree::printStringList(
    const char* name, 
    const char* const* strs, 
    uint32_t count,
    bool oneline
) {
    if (count == 0) {
        print("%s = []\n", name ? name : "NO_NAME");
    } else {
        if (oneline) {
            fprintf(stderr, "[wzhu] ");
            for (int i = 0; i < m_indent; ++i) {
                fputc(' ', stderr);
            }
            fprintf(stderr, "%s = [", name ? name : "NO_NAME");
            if (count >= 1) {
                fprintf(stderr, "%s", strs[0] ? strs[0] : "NULL");
            }
            for (uint32_t i = 1; i < count; i++) {
                fprintf(stderr, ", %s", strs[i] ? strs[i] : "NULL");
            }
            fprintf(stderr, "]\n");
        } else {
            print("%s = [\n", name ? name : "NO_NAME");
            {
                push();
                for (uint32_t i = 0; i < count; i++) {
                    print("%s\n", strs[i] ? strs[i] : "NULL");
                }
                pop();
            }
            print("]\n");
        }
    }
}

void WZHU_LogTree::printPhysicalDeviceFeatures(
    const char* name,
    const VkPhysicalDeviceFeatures* features,
    bool oneline 
) {
    if (features == NULL) {
        print("%s = []\n", name ? name : "NO_NAME");
        return;
    }

    std::vector<std::string> enabledNames;
    const VkBool32* elements = (const VkBool32*)features;
    for (std::size_t i = 0; i < sizeof(VkPhysicalDeviceFeatures) / sizeof(VkBool32); ++i) {
        if (elements[i] == VK_TRUE) {
            enabledNames.push_back(gk_physicalDeviceFeatureNames[i]);
        }
    }

    if (enabledNames.empty()) {
        print("%s = []\n", name ? name : "NO_NAME");
    } else {
        if (oneline) {
            fprintf(stderr, "[wzhu] ");
            for (int i = 0; i < m_indent; ++i) {
                fputc(' ', stderr);
            }
            fprintf(stderr, "%s = [", name ? name : "NO_NAME");
            if (enabledNames.size() >= 1) {
                fprintf(stderr, "%s", enabledNames[0].c_str());
            }
            for (std::size_t i = 1; i < enabledNames.size(); i++) {
                fprintf(stderr, ", %s", enabledNames[i].c_str());
            }
            fprintf(stderr, "]\n");
        } else {
            print("%s = [\n", name ? name : "NO_NAME");
            {
                push();
                for (std::size_t i = 0; i < enabledNames.size(); i++) {
                    print("%s\n", enabledNames[i].c_str());
                }
                pop();
            }
            print("]\n");
        }
    }
}

WZHU_CPUTimer::WZHU_CPUTimer() {
    m_start = std::chrono::high_resolution_clock::now();
}

uint32_t WZHU_CPUTimer::endForMsec() {
    auto end = std::chrono::high_resolution_clock::now();
    return (uint32_t)std::chrono::duration_cast<std::chrono::milliseconds>(end - m_start).count();
}

uint32_t WZHU_CPUTimer::endForUsec() {
    auto end = std::chrono::high_resolution_clock::now();
    return (uint32_t)std::chrono::duration_cast<std::chrono::microseconds>(end - m_start).count();
}

uint32_t WZHU_CPUTimer::endForNsec() {
    auto end = std::chrono::high_resolution_clock::now();
    return (uint32_t)std::chrono::duration_cast<std::chrono::nanoseconds>(end - m_start).count();
}
