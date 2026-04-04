cmake_minimum_required(VERSION 3.16)
project(wzhu_vulkan_profiling_layer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Vulkan REQUIRED)
set(WZHU_VULKAN_INCLUDE "${Vulkan_INCLUDE_DIRS}")

add_library(VkLayer_wzhu_profiling SHARED
    src/layer_entry_points.cpp
    src/layer_log.cpp
    src/config.cpp
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

add_custom_command(TARGET VkLayer_wzhu_profiling POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E create_symlink "${CMAKE_BINARY_DIR}/compile_commands.json" "${CMAKE_SOURCE_DIR}/compile_commands.json"
    COMMENT "Symlink compile_commands.json to project root"
)

# library_path is relative to share/vulkan/implicit_layer.d/VkLayer_wzhu_profiling.json so the
# Vulkan loader resolves the .so correctly for any install prefix (including cmake --install --prefix).
if(WIN32)
    set(WZHU_LAYER_RELATIVE_LIB_PATH "../../../bin/VkLayer_wzhu_profiling.dll")
else()
    set(WZHU_LAYER_RELATIVE_LIB_PATH "../../../lib/libVkLayer_wzhu_profiling.so")
endif()
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/layers/VkLayer_wzhu_profiling.json.in"
    "${CMAKE_CURRENT_BINARY_DIR}/VkLayer_wzhu_profiling.json"
    @ONLY
)

install(TARGETS VkLayer_wzhu_profiling
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/VkLayer_wzhu_profiling.json"
    DESTINATION share/vulkan/implicit_layer.d
)
if(UNIX)
    install(PROGRAMS "${CMAKE_CURRENT_SOURCE_DIR}/scripts/uninstall-wzhu-profiling-layer.sh"
        DESTINATION bin
    )
endif()

message(STATUS "VK_LAYER_WZHU_profiling: cmake --install installs manifest to \${CMAKE_INSTALL_PREFIX}/share/vulkan/implicit_layer.d/")
message(STATUS "  Implicit layers require disable_environment in the JSON (Vulkan loader 1.4+). Set env WZHU_PROFILING_DISABLE=1 to disable this layer.")
