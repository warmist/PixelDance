# NEEDS: sfml (static linked), LUA (better: luajit also static) IMGUI (aka dear imgui - compiled in)

cmake_minimum_required (VERSION 3.24)
project (pixeldance CXX C)


set(TARGET_NAME "pixeldance")

if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
    message(FATAL_ERROR "In-source builds are not allowed.")
endif()
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${PROJECT_SOURCE_DIR}/cmake/")


OPTION(BUILD_VERSION2 "Build second gen pixeldance" FALSE)
#dependancies

SET(IMGUI "../imgui" CACHE PATH "Path to imgui")
    
if(BUILD_VERSION2)

else()
    add_definitions(-DIMGUI_USER_CONFIG="imconfig-SFML.h")
    set(SFML_STATIC_LIBRARIES ON)
    FIND_PACKAGE( SFML 3 COMPONENTS Graphics Window System)
endif()
SET(LUA "../luajit" CACHE PATH "Path to lua")


#set(CMAKE_INSTALL_OPENMP_LIBRARIES TRUE) borked?
#set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION .)
#include(InstallRequiredSystemLibraries)

#message(STATUS OPENMP: ${MSVC_OPENMP_DIR})

option(EMBED_ASSETS "pack assets into binary" OFF)
if(EMBED_ASSETS)
    include(EmbedFileFTO)
    embed_file("${PROJECT_SOURCE_DIR}/assets/cp437_12x12.png")
else()
    set(EMBEDDED_HDRS)
    set(EMBEDDED_LIBS)
    add_definitions(-DNO_EMBEDS)
endif()
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

if(BUILD_VERSION2)
find_package(Vulkan REQUIRED) 
endif()

set(SRC_VER_1
    src/main.cpp
    src/imgui-SFML.cpp
    src/lua_buffers.cpp
    src/shaders.cpp
    src/textures.cpp
    src/buffer_data.cpp
    src/lua_opencl.cpp
    src/limgui.cpp
)
set(SRC_VER_2
    src/main_win32.cpp
    src/lua_vk.cpp
    ${IMGUI}/backends/imgui_impl_win32.cpp
    ${IMGUI}/backends/imgui_impl_vulkan.cpp
)
set(SRCS
    ${IMGUI}/imgui.cpp
    #${IMGUI}/imgui_demo.cpp
    ${IMGUI}/imgui_draw.cpp
    ${IMGUI}/imgui_tables.cpp
    ${IMGUI}/imgui_widgets.cpp
    src/filesys.cpp
    src/lua_random.cpp
    src/matrix.cpp
    src/lua_kd.cpp

)
set(HDRS_VER_1
    src/imconfig-SFML.h
    src/imgui-SFML_export.h
    src/imgui-SFML.h
    src/lua_buffers.h
    src/shaders.h
    src/gl_lite.h
    src/cl_lite.h
    src/textures.hpp
    src/buffer_data.hpp
    src/lua_opencl.h
    src/lua_vk.h
    src/limgui.h
)
set(HDRS_VER_2
    src/win32_lite.h
)
set(HDRS
    src/filesys.h
    src/stb_image.h
    src/stb_image_write.h
    src/lua_random.h
    src/pcg_random.h
    src/matrix.h
    src/nanoflann.hpp
    src/lua_kd.h
    ${IMGUI}/imgui.h
    ${LUA}/lua.hpp
    ${LUA}/lualib.h
)

if(BUILD_VERSION2)
    list(APPEND SRCS ${SRC_VER_2})
    list(APPEND HDRS ${HDRS_VER_2})
else()
    list(APPEND SRCS ${SRC_VER_1})
    list(APPEND HDRS ${HDRS_VER_1})
endif()

add_executable(${TARGET_NAME}
  ${SRCS} ${HDRS}
  ${EMBEDDED_HDRS} ${EMBEDDED_LIBS}
)

target_link_libraries(${TARGET_NAME} ${LUA}/lua51.lib)
if(BUILD_VERSION2)
    target_link_libraries(${TARGET_NAME} Vulkan::Vulkan )
else()
    target_link_libraries(${TARGET_NAME}  SFML::Graphics SFML::Window SFML::System )
endif()

include_directories(${CMAKE_CURRENT_BINARY_DIR})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)
INCLUDE_DIRECTORIES(${IMGUI})
INCLUDE_DIRECTORIES(${LUA})



install(TARGETS ${TARGET_NAME} DESTINATION .)
install(DIRECTORY projects DESTINATION .)