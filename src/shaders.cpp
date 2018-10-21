#include "shaders.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include "gl_lite.h"

#include <vector>

struct shader_program {
	GLuint id = -1;
};
static shader_program* check(lua_State* L, int id) { return *reinterpret_cast<shader_program**>(luaL_checkudata(L, id, "shader")); }
static int use_shader(lua_State* L)
{
	auto s = check(L, 1);
	glUseProgram(s->id);
	return 0;
}
template<typename T>
static void set_uniform_args(lua_State* L,GLint uloc, int arg_start,int num_args);
template<typename T>
static int set_uniform(lua_State* L)
{
	auto s = check(L, 1);
	GLint uloc;
	if(lua_isstring(L,2))
	{
		auto uid= luaL_checkstring(L, 2);
		uloc=glGetUniformLocation(s->id, uid);
		//if (uloc == -1)//NOTE: the linker can optimize out the uniform and then we'll get -1 -.-
		//	luaL_error(L,"could not find uniform named: %s", uid);
	}
	else
	{
		uloc = luaL_checkint(L, 2);
	}
	const int arg_offset = 2;
	int num_args = lua_gettop(L)- arg_offset;
	if( num_args<1 || num_args>4 )
		luaL_error(L, "invalid count of arguments: %d", num_args);
	
	set_uniform_args<T>(L, uloc, arg_offset, num_args);
	lua_pushinteger(L,uloc);
	return 1;
}
template<>
static void set_uniform_args<float>(lua_State* L, GLint uloc, int arg_start, int num_args)
{
	GLfloat buf[4] = { 0 };
	for (int i = 0; i < num_args; i++)
	{
		buf[i] = luaL_checknumber(L, i + arg_start + 1);
	}
	switch (num_args)
	{
	case 1:
		glUniform1f(uloc, buf[0]);
		break;
	case 2:
		glUniform2f(uloc, buf[0], buf[1]);
		break;
	case 3:
		glUniform3f(uloc, buf[0], buf[1], buf[2]);
		break;
	case 4:
		glUniform4f(uloc, buf[0], buf[1], buf[2], buf[3]);
		break;
	default:
		luaL_error(L, "reached unreachable area?! !!ERROR!!");
		break;
	}
}
template<>
static void set_uniform_args<int>(lua_State* L, GLint uloc, int arg_start, int num_args)
{
	GLint buf[4] = { 0 };
	for (int i = 0; i < num_args; i++)
	{
		buf[i] = luaL_checkinteger(L, i + arg_start + 1);
	}
	switch (num_args)
	{
	case 1:
		glUniform1i(uloc, buf[0]);
		break;
	case 2:
		glUniform2i(uloc, buf[0], buf[1]);
		break;
	case 3:
		glUniform3i(uloc, buf[0], buf[1], buf[2]);
		break;
	case 4:
		glUniform4i(uloc, buf[0], buf[1], buf[2], buf[3]);
		break;
	default:
		luaL_error(L, "reached unreachable area?! !!ERROR!!");
		break;
	}
}
static int del_shader(lua_State* L)
{
	auto s = check(L, 1);
	glDeleteProgram(s->id);
	delete s;
	return 0;
}
static void get_shader_log(std::vector<char>& err,GLuint shader)
{
	int InfoLogLength;
	glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &InfoLogLength);
	size_t err_end = err.size();
	err.resize(err_end +InfoLogLength + 1);

	glGetShaderInfoLog(shader, InfoLogLength, NULL, &err[err_end]);
}
const GLfloat quad_pos[] = {
	-1.0f,-1.0f,0.0f,
	1.0f,-1.0f,0.0f,
	1.0f, 1.0f,0.0f,
	-1.0f, 1.0f,0.0f,
};
static int draw_quad(lua_State* L)
{
	auto s = check(L, 1);
	glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 50);
	auto pos_idx=glGetAttribLocation(s->id,"position");

	glEnableVertexAttribArray(pos_idx);
	glVertexAttribPointer(pos_idx, 3, GL_FLOAT, false, 0, quad_pos); // vertex_data is a float*, 3 per vertex, representing the position of each vertex
	glDrawArrays(GL_QUADS, 0, 4); // vertex_count is an integer containing the number of indices to be rendered
	glDisableVertexAttribArray(pos_idx);
	return 0;
}
void debug_program(shader_program& s)
{
	GLint i;
	GLint count;

	GLint size; // size of the variable
	GLenum type; // type of the variable (float, vec3 or mat4, etc)

	const GLsizei bufSize = 16; // maximum name length
	GLchar name[bufSize]; // variable name in GLSL
	GLsizei length; // name length

	glGetProgramiv(s.id, GL_ACTIVE_ATTRIBUTES, &count);
	printf("Active Attributes: %d\n", count);

	for (i = 0; i < count; i++)
	{
		glGetActiveAttrib(s.id, (GLuint)i, bufSize, &length, &size, &type, name);

		printf("Attribute #%d Type: %u Name: %s\n", i, type, name);
	}

	glGetProgramiv(s.id, GL_ACTIVE_UNIFORMS, &count);
	printf("Active Uniforms: %d\n", count);

	for (i = 0; i < count; i++)
	{
		glGetActiveUniform(s.id, (GLuint)i, bufSize, &length, &size, &type, name);

		printf("Uniform #%d Type: %u Name: %s\n", i, type, name);
	}

}
static int make_shader(lua_State* L, const char* vertex, const char* fragment) {
	//TODO: check ret->id
	auto make_shader=[L](const char* source,GLuint type) {
		auto ret_s = glCreateShader(type);
		//TODO: check ret
		GLint len = strlen(source);
		glShaderSource(ret_s, 1, &source, &len);
		glCompileShader(ret_s);
		GLint status;
		glGetShaderiv(ret_s, GL_COMPILE_STATUS, &status);
		if(!status)
		{
			std::vector<char> err;
			get_shader_log(err, ret_s);
			luaL_error(L, "\n\terror compiling shader:%s", err.data());
		}
		return ret_s;
	};
	auto vert_shader = make_shader(vertex,GL_VERTEX_SHADER);
	auto frag_shader = make_shader(fragment,GL_FRAGMENT_SHADER);

	auto ret = new shader_program;
	auto np = lua_newuserdata(L, sizeof(ret));
	*reinterpret_cast<shader_program**>(np) = ret;
	ret->id = glCreateProgram();
	glAttachShader(ret->id, vert_shader);
	glAttachShader(ret->id, frag_shader);
	glLinkProgram(ret->id);

	glDeleteShader(vert_shader);
	glDeleteShader(frag_shader);
	{
		
		GLint status;
		glGetProgramiv(ret->id, GL_LINK_STATUS, &status);
		if(!status)
		{
			int InfoLogLength;
			glGetProgramiv(ret->id, GL_INFO_LOG_LENGTH, &InfoLogLength);
			std::vector<char> err;
			err.resize(InfoLogLength + 1);
			glGetProgramInfoLog(ret->id, InfoLogLength, NULL, err.data());
			glDeleteProgram(ret->id);
			delete ret;
			luaL_error(L, "error linking shader:%s", err.data());
		}
	}
#ifdef SHADER_DEBUG
	debug_program(*ret);
#endif
	if (luaL_newmetatable(L, "shader"))
	{
		lua_pushcfunction(L, del_shader);
		lua_setfield(L, -2, "__gc");

		lua_pushcfunction(L, use_shader);
		lua_setfield(L, -2, "use");

		lua_pushcfunction(L, set_uniform<float>); 
		lua_setfield(L, -2, "set");

		lua_pushcfunction(L, set_uniform<float>);
		lua_setfield(L, -2, "set_f"); 

		lua_pushcfunction(L, set_uniform<int>); 
		lua_setfield(L, -2, "set_i");

		lua_pushcfunction(L, draw_quad);
		lua_setfield(L, -2, "draw_quad");
		/*
		lua_pushcfunction(L, set_variable); //either uniform or attribute
		lua_setfield(L, -2, "set");

		lua_pushcfunction(L, list_uniforms);
		lua_setfield(L, -2, "uniforms");

		lua_pushcfunction(L, list_attributes);
		lua_setfield(L, -2, "attributes");
		*/

		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);
	return 1;
}
const char* default_vertex_shader = 
R"(
#version 330

layout(location = 0) in vec3 position;

out vec3 pos;
void main()
{
    gl_Position.xyz = position;
    gl_Position.w = 1.0;
    pos=position;
}
)";
int make_lua_shader_prog(lua_State* L )
{
	int v = lua_gettop(L);
	if (v == 1)
	{
		//expecting a fragment shader
		const char* fs = luaL_checkstring(L, 1);
		return make_shader(L, default_vertex_shader, fs);
	}
	else if (v == 2)
	{
		const char* vs = luaL_checkstring(L, 1);
		const char* fs = luaL_checkstring(L, 2);
		//expecting a vertex+fragment shader
		return make_shader(L, vs, fs);
	}
	else
	{
		luaL_error(L, "expected (optional) vertex shader source and fragment shader source");
		return 0;
	}
}
static int use_empty_shader(lua_State* L)
{
	glUseProgram(0); //TODO: nicer way of doing this?
	return 0;
}
static const luaL_Reg lua_shaders_lib[] = {
	{ "Make",make_lua_shader_prog },
	{ "use_empty",use_empty_shader},
	{ NULL, NULL }
};

int lua_open_shaders(lua_State * L)
{
	luaL_newlib(L, lua_shaders_lib);

	lua_setglobal(L, "shaders");

	return 1;
}
