cmake_minimum_required(VERSION 3.16)
project(wzhu_vulkan_profiling_layer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Vulkan REQUIRED)
set(WZHU_VULKAN_INCLUDE "${Vulkan_INCLUDE_DIRS}")

add_library(VkLayer_wzhu_profiling SHARED
    src/layer_core/wzhu_layer.cpp
    src/layer_core/wzhu_layer_dispatch.cpp
    src/utils/wzhu_timing_statistics.cpp
    src/hook_device.cpp
    src/hook_instance.cpp
    src/hook_dispatch.cpp
)

set_target_properties(VkLayer_wzhu_profiling PROPERTIES
    OUTPUT_NAME "VkLayer_wzhu_profiling"
)

target_include_directories(VkLayer_wzhu_profiling PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${WZHU_VULKAN_INCLUDE}"
)

if(WIN32)
    target_compile_options(VkLayer_wzhu_profiling PRIVATE 
        /W4 /permissive-
    )
    target_compile_definitions(VkLayer_wzhu_profiling PRIVATE
        VK_USE_PLATFORM_WIN32_KHR=1
        NOMINMAX
        WIN32_LEAN_AND_MEAN
    )
else()
    target_compile_options(VkLayer_wzhu_profiling PRIVATE 
        -Wall -Wextra -Wno-unused-parameter
    )
    target_compile_definitions(VkLayer_wzhu_profiling PRIVATE
        VK_USE_PLATFORM_XLIB_KHR=1
        VK_USE_PLATFORM_XCB_KHR=1
        VK_USE_PLATFORM_WAYLAND_KHR=1
    )
endif()

install(TARGETS VkLayer_wzhu_profiling
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES layers/VkLayer_wzhu_profiling.json
    DESTINATION share/vulkan/explicit_layer.d
)
