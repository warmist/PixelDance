#include "lua_buffers.h"

#include "SFML\Graphics.hpp"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include <unordered_map>

#include "stb_image_write.h"

enum class buffer_type {
	vector_u8x4,
	vector_float,
};
struct u8x4 {
	uint8_t r, g, b, a;
};
struct buffer_entry
{
	int w;
	buffer_type t;
};
std::unordered_map<void*, buffer_entry> buffer_registry;

void get_current_size(lua_State* L, int& x, int& y)
{
	lua_getglobal(L, "STATE");
	lua_getfield(L, -1, "size");

	lua_rawgeti(L, -1, 1);
	x=lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_rawgeti(L, -1, 2);
	y = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_pop(L, 2);
}



template <typename T>
struct buffer_value_access{
static constexpr char* name();
static int push(lua_State* L, const T& v);
static T to_element(lua_State* L, int id);
static std::vector<T>* check(lua_State* L, int id) { return *reinterpret_cast<std::vector<T>**>(luaL_checkudata(L, id, name())); }
static int get_buffer(lua_State* L)
{
	auto ptr = buffer_value_access<T>::check(L, 1);
	int x = luaL_checkinteger(L, 2);
	int y = luaL_checkinteger(L, 3);
	auto e = buffer_registry[ptr];
	auto& v = ptr->at(x*e.w + y); \
	return buffer_value_access<T>::push(L, v);
}
static int set_buffer(lua_State* L) {
	auto ptr = buffer_value_access<T>::check(L, 1);
	int x = luaL_checkinteger(L, 2);
	int y = luaL_checkinteger(L, 3);
	auto new_value = buffer_value_access<T>::to_element(L, 4);
	auto e = buffer_registry[ptr];
	ptr->at(x*e.w + y) = new_value;
	return 0;
}
static int del_buffer(lua_State* L) {	
	auto ptr= check(L, 1);
	buffer_registry.erase(ptr); delete ptr;
	return 0;
}
static int len_buffer(lua_State* L) {
	auto ptr = check(L, 1);
	lua_pushnumber(L, ptr->size());
	return 1;
}
static int index_buffer(lua_State* L) {
	auto ptr = check(L, 1);
	int id = luaL_checkinteger(L, 2);
	auto& v = ptr->at(id);
	return push(L, v);
}
static int newindex_buffer(lua_State* L){
	auto ptr = check(L, 1);
	int id = luaL_checkinteger(L, 2);
	auto new_value = to_element(L, 3);
	ptr->at(id) = new_value;
	return 0;
}
static void resize_buffer(void* d, int w, int h){
	auto p = reinterpret_cast<std::vector<T>*>(d);
	p->resize(w*h);
	buffer_registry[d].w = w;
}
static void add_special_methods(lua_State* L);
static int make_buffer(lua_State* L, int w, int h){
	auto ret = new std::vector<T>(w*h);
	buffer_registry[ret].w = w;
	auto np=lua_newuserdata(L,sizeof(ret));
	*reinterpret_cast<std::vector<T>**>(np)=ret;
	if (luaL_newmetatable(L, name()))
	{
		lua_pushcfunction(L, del_buffer);
		lua_setfield(L, -2, "__gc");
		lua_pushcfunction(L, len_buffer);
		lua_setfield(L, -2, "__len");

		lua_pushcfunction(L, get_buffer);
		lua_setfield(L, -2, "get");
		lua_pushcfunction(L, set_buffer);
		lua_setfield(L, -2, "set");

		add_special_methods(L);

		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);
	return 1;
}
};

static int make_lua_auto_buffer(lua_State* L)
{
	const char* buf_type = luaL_checkstring(L, 1);
	int x, y;
	get_current_size(L, x, y);

	if (strcmp(buf_type, "color")==0)
	{
		return buffer_value_access<u8x4>::make_buffer(L,x,y);
	} else if (strcmp(buf_type, "float") == 0)
	{
		return buffer_value_access<float>::make_buffer(L, x, y);
	}
}

static const luaL_Reg lua_buffers_lib[] = {
	{ "Make",make_lua_auto_buffer },
	{ NULL, NULL }
};

int lua_open_buffers(lua_State * L)
{
	luaL_newlib(L, lua_buffers_lib);

	lua_setglobal(L, "buffers");

	return 1;
}

void resize_lua_buffers(int w, int h)
{
	for (auto& v : buffer_registry)
	{
		switch (v.second.t)
		{
#define DO_BUFFER_RESIZE(tname,name) case buffer_type::vector_##tname: buffer_value_access<tname>::resize_buffer(v.first,w,h);break
		DO_BUFFER_RESIZE(u8x4, color);
		DO_BUFFER_RESIZE(float, float);
		default:
			break;
		}
	}
}
#undef DO_BUFFER_RESIZE

template<>
static constexpr char * buffer_value_access<u8x4>::name()
{
	return "color_buffer";
}

template<>
static int buffer_value_access<u8x4>::push(lua_State * L, const u8x4& v)
{
	lua_newtable(L);

	lua_pushinteger(L, v.r);
	lua_rawseti(L, -2, 1);

	lua_pushinteger(L, v.g);
	lua_rawseti(L, -2, 2);

	lua_pushinteger(L, v.b);
	lua_rawseti(L, -2, 3);

	lua_pushinteger(L, v.a);
	lua_rawseti(L, -2, 4);

	return 1;
}

template<>
static u8x4 buffer_value_access<u8x4>::to_element(lua_State * L, int id)
{
	u8x4 ret;
	luaL_checktype(L, id, LUA_TTABLE);
	lua_rawgeti(L, id, 1); ret.r = lua_tointeger(L, -1); lua_pop(L, 1);
	lua_rawgeti(L, id, 2); ret.g = lua_tointeger(L, -1); lua_pop(L, 1);
	lua_rawgeti(L, id, 3); ret.b = lua_tointeger(L, -1); lua_pop(L, 1);
	lua_rawgeti(L, id, 4); ret.a = lua_tointeger(L, -1); lua_pop(L, 1);
	return ret;
}

static int present_buffer(lua_State* L)
{
	auto ptr = buffer_value_access<u8x4>::check(L, 1);
	lua_getglobal(L, "STATE");
	lua_getfield(L, -1, "texture");

	auto tex = reinterpret_cast<sf::Texture*>(lua_touserdata(L, -1));
	lua_pop(L, 2);
	tex->update(reinterpret_cast<const sf::Uint8*>(ptr->data()));
	return 0;
}

static int save_image(lua_State* L)
{
	auto ptr = buffer_value_access<u8x4>::check(L, 1);
	auto path = luaL_checkstring(L, 2);

	auto e = buffer_registry[ptr];
	auto ret=stbi_write_png(path, e.w, ptr->size() / e.w, 4, ptr->data(), e.w * 4);
	lua_pushinteger(L, ret);
	return 1;
}

template<>
static void buffer_value_access<u8x4>::add_special_methods(lua_State * L)
{
	lua_pushcfunction(L, present_buffer);
	lua_setfield(L, -2, "present");
	
	lua_pushcfunction(L, save_image);
	lua_setfield(L, -2, "save");
}

template<>
static constexpr char * buffer_value_access<float>::name()
{
	return "float_buffer";
}

template<>
static int buffer_value_access<float>::push(lua_State * L, const float& v)
{
	lua_pushnumber(L, v);
	return 1;
}

template<>
static float buffer_value_access<float>::to_element(lua_State * L, int id)
{
	return luaL_checknumber(L, id);
}

template<>
static void buffer_value_access<float>::add_special_methods(lua_State * L)
{
	//nothing to add :S
}