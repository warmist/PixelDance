#pragma once

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

int lua_open_imgui(lua_State* L);

void fixup_imgui_state();