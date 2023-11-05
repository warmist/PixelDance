#pragma once

struct lua_State;
int lua_open_vulkan(lua_State* L);

int init_vulkan(void* hwnd,void* hinstance);