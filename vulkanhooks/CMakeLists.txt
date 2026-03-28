cmake_minimum_required(VERSION 3.16)
project(wzhu_vulkan_profiling_layer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(WZHU_VULKAN_USE_SYSTEM_HEADERS "Use Vulkan-Headers from VULKAN_SDK / system instead of FetchContent" OFF)

if(WZHU_VULKAN_USE_SYSTEM_HEADERS)
  find_package(Vulkan REQUIRED)
  set(WZHU_VULKAN_INCLUDE "${Vulkan_INCLUDE_DIRS}")
else()
  include(FetchContent)
  FetchContent_Declare(
    VulkanHeaders
    GIT_REPOSITORY https://github.com/KhronosGroup/Vulkan-Headers.git
    GIT_TAG v1.3.280
  )
  FetchContent_MakeAvailable(VulkanHeaders)
  if(DEFINED VulkanHeaders_SOURCE_DIR)
    set(WZHU_VULKAN_INCLUDE "${VulkanHeaders_SOURCE_DIR}/include")
  else()
    set(WZHU_VULKAN_INCLUDE "${vulkanheaders_SOURCE_DIR}/include")
  endif()
endif()

add_library(VkLayer_wzhu_profiling SHARED
  src/layer.cpp
)

target_include_directories(VkLayer_wzhu_profiling PRIVATE
  "${WZHU_VULKAN_INCLUDE}"
)

if(WIN32)
  target_compile_definitions(VkLayer_wzhu_profiling PRIVATE
    VK_USE_PLATFORM_WIN32_KHR=1
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
elseif(APPLE)
  target_compile_definitions(VkLayer_wzhu_profiling PRIVATE
    VK_USE_PLATFORM_METAL_EXT=1
  )
else()
  target_compile_definitions(VkLayer_wzhu_profiling PRIVATE
    VK_USE_PLATFORM_XLIB_KHR=1
    VK_USE_PLATFORM_XCB_KHR=1
    VK_USE_PLATFORM_WAYLAND_KHR=1
  )
endif()

if(MSVC)
  target_compile_options(VkLayer_wzhu_profiling PRIVATE /W4 /permissive-)
else()
  target_compile_options(VkLayer_wzhu_profiling PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

set_target_properties(VkLayer_wzhu_profiling PROPERTIES
  OUTPUT_NAME "VkLayer_wzhu_profiling"
)

install(TARGETS VkLayer_wzhu_profiling
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
)
install(FILES layers/VkLayer_wzhu_profiling.json
  DESTINATION share/vulkan/explicit_layer.d
)
