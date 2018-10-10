#include "lua_random.h"

#define PCG_RANDOM_IMPLEMENTATION
#include "pcg_random.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include <limits>
static pcg32_random_t* check(lua_State* L, int id) { return reinterpret_cast<pcg32_random_t*>(luaL_checkudata(L, id, "pcg_random")); }

static int pcg_seed(lua_State* L)
{
	auto r = check(L, 1);
	
	uint64_t seed = luaL_optinteger(L, 2, pcg32_random() << 4 | pcg32_random());
	uint64_t seq = luaL_optinteger(L, 3, 0);
	pcg32_srandom_r(r, seed, seq);
	return 0;
}
static int lua_gen(lua_State* L, pcg32_random_t* r,int idx)
{
	int num_args = lua_gettop(L) - idx;
	int lower = 1;
	int upper = 0;
	if ( num_args == 0)
	{
		//no args, return [0,1] float
		uint32_t ret=pcg32_random_r(r);
		lua_pushnumber(L, LUA_NUMBER(ret) / LUA_NUMBER(std::numeric_limits<uint32_t>::max()));
		return 1;
	}
	else if (num_args == 1)
	{
		upper = luaL_checkint(L, idx + 1);
	}
	else
	{
		lower = luaL_checkint(L, idx + 1);
		upper = luaL_checkint(L, idx + 2);
	}
	if (upper < lower)
	{
		luaL_error(L,"empty random range");
	}
	else if (upper == lower)
	{
		lua_pushinteger(L, upper);
		return 1;
	}
	lua_pushinteger(L, int32_t(pcg32_boundedrand_r(r, upper - lower+1)) + lower);
	return 1;
}
static int pcg_gen(lua_State* L)
{
	auto r = check(L, 1);
	return lua_gen(L, r, 1);
}
static int gen_number(lua_State* L)
{
	return lua_gen(L, &pcg32_global, 0);
}
static int make_random_gen(lua_State* L) {

	auto np = lua_newuserdata(L, sizeof(pcg32_random_t));
	auto ret=reinterpret_cast<pcg32_random_t*>(np);

	if (luaL_newmetatable(L, "pcg_random"))
	{
		//lua_pushcfunction(L, del_random);
		//lua_setfield(L, -2, "__gc");
		lua_pushcfunction(L, pcg_seed);
		lua_setfield(L, -2, "seed");

		lua_pushcfunction(L, pcg_gen);
		lua_setfield(L, -2, "__call");

		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);
	return 1;
}

static const luaL_Reg lua_random_lib[] = {
    { "Make",make_random_gen },
	{ "gen",gen_number},
    { NULL, NULL }
};

int lua_open_random(lua_State* L)
{
	luaL_newlib(L, lua_random_lib);

	lua_setglobal(L, "pcg_rand");

	return 1;
}