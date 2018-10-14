#include "textures.hpp"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include "gl_lite.h"

struct texture {
	GLuint id;
};
static texture* check(lua_State* L, int id) { return *reinterpret_cast<texture**>(luaL_checkudata(L, id, "texture")); }
static int use_texture(lua_State* L)
{
	auto s = check(L, 1);
	auto num=luaL_checkint(L, 2);
	glActiveTexture(num+GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, s->id);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	return 0;
}
struct gl_tex_format {
	GLint internal_format;
	GLint format;
	GLenum type;
};
static const gl_tex_format formats[] = {
	{ GL_RGBA8,GL_RGBA,GL_UNSIGNED_BYTE },
	{ GL_RGBA32F,GL_RGBA,GL_FLOAT },
	{ GL_R32F,GL_RED,GL_FLOAT },
};
//if second arg is not ptr to data, create empty texture!
static int set_texture_data(lua_State* L)
{
	auto s = check(L, 1);
	const void* data=nullptr;
	int arg = 3;
	if (lua_type(L, 2) == 10) //cdata
	{
		data = lua_topointer(L, 2); //TODO: check pointer?
	}
	else
		arg = 2;
	auto w = luaL_checkint(L, arg++);
	auto h = luaL_checkint(L, arg++);
	auto format = luaL_optint(L, arg++, 0);

	auto f = formats[format];
	glTexImage2D(GL_TEXTURE_2D, 0, f.internal_format, w, h, 0, f.format, f.type, data);
	return 0;
}
static int get_texture_data(lua_State* L)
{
	auto s = check(L, 1);

	void* data = const_cast<void*>(lua_topointer(L, 2));
	auto w = luaL_checkint(L, 3);
	auto h = luaL_checkint(L, 4);
	auto format = luaL_optint(L, 5, 0);

	auto f = formats[format];
	glGetTexImage(GL_TEXTURE_2D, 0, f.format, f.type, data);
	return 0;
}
GLuint fbuffer = -1;
static int set_render_target(lua_State* L)
{
	auto s = check(L, 1);
	if (fbuffer == -1)
	{
		glGenFramebuffers(1, &fbuffer);
	}
	glBindFramebuffer(GL_FRAMEBUFFER, fbuffer);
	glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, s->id, 0);

	/*??*/
	GLenum DrawBuffers[1] = { GL_COLOR_ATTACHMENT0 };
	glDrawBuffers(1, DrawBuffers);

	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		lua_pushboolean(L, false);
	else
		lua_pushboolean(L, true);
	return 1;
}
static int del_texture(lua_State* L)
{
	auto s = check(L, 1);
	glDeleteTextures(1, &s->id);
	return 0;
}

static int make_lua_texture(lua_State* L)
{
	auto ret = new texture;
	auto np = lua_newuserdata(L, sizeof(ret));
	*reinterpret_cast<texture**>(np) = ret;
	glGenTextures(1,&ret->id);

	if (luaL_newmetatable(L, "texture"))
	{
		lua_pushcfunction(L, del_texture);
		lua_setfield(L, -2, "__gc");

		lua_pushcfunction(L, use_texture);
		lua_setfield(L, -2, "use");

		lua_pushcfunction(L, set_texture_data);
		lua_setfield(L, -2, "set");

		lua_pushcfunction(L, get_texture_data);
		lua_setfield(L, -2, "read");

		lua_pushcfunction(L, set_render_target);
		lua_setfield(L, -2, "render_to");

		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);
	return 1;
}

static const luaL_Reg lua_textures_lib[] = {
	{ "Make",make_lua_texture },
	{ NULL, NULL }
};

int lua_open_textures(lua_State * L)
{
	luaL_newlib(L, lua_textures_lib);

	lua_setglobal(L, "textures");

	return 1;
}
