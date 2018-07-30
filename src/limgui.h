#pragma once

struct lua_State;
int lua_open_imgui(lua_State* L);
//NOTE: call this because on error, there might be unmatched imgui::begin/end(s)
void fixup_imgui_state();