# NEEDS: sfml (static linked), LUA (better: luajit also static) IMGUI (aka dear imgui - compiled in)

cmake_minimum_required (VERSION 3.10)
project (pixeldance CXX C)


set(TARGET_NAME "pixeldance")

if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
   message(FATAL_ERROR "In-source builds are not allowed.")
endif()
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${PROJECT_SOURCE_DIR}/cmake/")

#dependancies
set(SFML_STATIC_LIBRARIES TRUE)
FIND_PACKAGE( SFML 2.4 COMPONENTS graphics window system)


SET(IMGUI "../imgui" CACHE PATH "Path to imgui")
add_definitions(-DIMGUI_USER_CONFIG="imconfig-SFML.h")

SET(LUA "../luajit" CACHE PATH "Path to lua")


set(CMAKE_INSTALL_OPENMP_LIBRARIES TRUE)
set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION .)
include(InstallRequiredSystemLibraries)

message(STATUS OPENMP: ${MSVC_OPENMP_DIR})

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


set(SRCS
  src/main.cpp
  src/imgui-SFML.cpp
  src/filesys.cpp
  src/limgui.cpp
  src/lua_buffers.cpp
  src/shaders.cpp
  src/textures.cpp
  src/buffer_data.cpp
  src/lua_random.cpp
  src/matrix.cpp
  src/lua_kd.cpp
  ${IMGUI}/imgui.cpp
  ${IMGUI}/imgui_draw.cpp
  ${IMGUI}/imgui_demo.cpp
)

set(HDRS
  src/imconfig-SFML.h
  src/imgui-SFML.h
  src/filesys.h
  src/limgui.h
  src/stb_image.h
  src/stb_image_write.h
  src/lua_buffers.h
  src/shaders.h
  src/gl_lite.h
  src/textures.hpp
  src/buffer_data.hpp
  src/lua_random.h
  src/pcg_random.h
  src/matrix.h
  src/nanoflann.hpp
  src/lua_kd.h
  ${LUA}/lua.hpp
  ${LUA}/lualib.h
)
include_directories(${SFML_INCLUDE_DIR})
include_directories(${CMAKE_CURRENT_BINARY_DIR})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)
INCLUDE_DIRECTORIES(${IMGUI})
INCLUDE_DIRECTORIES(${LUA})

add_executable(${TARGET_NAME}
  ${SRCS} ${HDRS}
  ${EMBEDDED_HDRS} ${EMBEDDED_LIBS}
)

target_link_libraries(${TARGET_NAME}  ${SFML_LIBRARIES} ${SFML_DEPENDENCIES} ${LUA}/lua51.lib )
install(TARGETS ${TARGET_NAME} DESTINATION .)
install(DIRECTORY projects DESTINATION .)