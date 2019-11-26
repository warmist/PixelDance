#include "buffer_data.hpp"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include "gl_lite.h"

struct buffer_data {
    GLuint id;
};
static buffer_data* check(lua_State* L, int id) { return *reinterpret_cast<buffer_data**>(luaL_checkudata(L, id, "buffer_data")); }

static int use_buffer(lua_State* L)
{
    auto s = check(L, 1);
    glBindBuffer(GL_ARRAY_BUFFER, s->id);
    return 0;
}
//if second arg is not ptr to data, create empty [s]texture![/s] buffer
static int set_buffer_data(lua_State* L)
{
    auto s = check(L, 1);
    const void* data = nullptr;
    int arg = 3;
    if ((lua_type(L, 2) == 10) /*cdata*/ || (lua_type(L, 2) == LUA_TLIGHTUSERDATA))
    {
        data = lua_topointer(L, 2); //TODO: check pointer?
    }
    else
        arg = 2;
    auto size = luaL_checkint(L, arg++);

    glBufferData(GL_ARRAY_BUFFER, size, data, GL_DYNAMIC_DRAW); //TODO: other hints?

    return 0;
}
static int get_buffer_data(lua_State* L)
{
    auto s = check(L, 1);

    void* data = const_cast<void*>(lua_topointer(L, 2));
    auto size = luaL_checkint(L, 3);
    auto offset = luaL_optint(L, 4, 0);

    glGetNamedBufferSubData(s->id, offset, size, data);

    return 0;
}
static int bind_to_feedback(lua_State* L)
{
    auto s = check(L, 1);
    auto offset = luaL_optint(L, 2, 0);

    glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, s->id);

    return 0;
}

static int del_buffer_data(lua_State* L)
{
    auto s = check(L, 1);
    glDeleteBuffers(1, &s->id);
    return 0;
}

static int make_lua_buffer_data(lua_State* L)
{
    auto ret = new buffer_data;
    auto np = lua_newuserdata(L, sizeof(ret));
    *reinterpret_cast<buffer_data**>(np) = ret;
    glGenBuffers(1, &ret->id);

    if (luaL_newmetatable(L, "buffer_data"))
    {
        lua_pushcfunction(L, del_buffer_data);
        lua_setfield(L, -2, "__gc");

        lua_pushcfunction(L, use_buffer);
        lua_setfield(L, -2, "use");

        lua_pushcfunction(L, set_buffer_data);
        lua_setfield(L, -2, "set");

        lua_pushcfunction(L, get_buffer_data);
        lua_setfield(L, -2, "read");

        lua_pushcfunction(L, bind_to_feedback);
        lua_setfield(L, -2, "bind_to_feedback");

        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}

static const luaL_Reg lua_buffer_data_lib[] = {
    { "Make",make_lua_buffer_data },
    { NULL, NULL }
};

int lua_open_buffer_data(lua_State * L)
{
    luaL_newlib(L, lua_buffer_data_lib);

    lua_setglobal(L, "buffer_data");

    return 1;
}
