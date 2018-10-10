#include "lua_random.h"

#define PCG_RANDOM_IMPLEMENTATION
#include "pcg_random.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"


static const luaL_Reg lua_random_lib[] = {
    { "Make",make_random_gen },
    { NULL, NULL }
};

int lua_open_buffers(lua_State * L)
{
    luaL_newlib(L, lua_random_lib);

    lua_setglobal(L, "pcg_rand");

    return 1;
}
int lua_open_random(lua_State* L)
{

}