#pragma once

struct lua_State;
int lua_open_buffers(lua_State* L);

void resize_lua_buffers(int w,int h);