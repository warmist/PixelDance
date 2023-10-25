/*
gl_lite.h - Single-header multi-platform OpenGL function loader

----------------------------------------------------------------------------
USAGE
----------------------------------------------------------------------------
1) Add the following lines in exactly one of your cpp files to compile the
implementation:

#define GL_LITE_IMPLEMENTATION
#include "gl_lite.h"

2) In all other files in which you want to use OpenGL functions, simply
include this header file as follows:

#include "gl_lite.h"

3) Call gl_lite_init() before using any OpenGL function and after you have a
valid OpenGL context.

----------------------------------------------------------------------------
LICENSE
----------------------------------------------------------------------------
This software is in the public domain. Where that dedication is not
recognized, you are granted a perpetual, irrevocable license to copy,
distribute, and modify this file as you see fit.
*/
/*NOTE(warmist): found here - https://github.com/ApoorvaJ/Papaya/blob/3808e39b0f45d4ca4972621c847586e4060c042a/src/libs/gl_lite.h
	Changes:
		* PAPAYA_ -> GLLITE_
		* already linking to opengl32.dll so we can just extern the wglGetProcAddress
		* split init_gl_lite to be under ifdef(platform)
	TODO: minize windows.h include
*/
#ifndef GL_LITE_H
#define GL_LITE_H

#if defined(__linux__)
#include <dlfcn.h>
#define GLDECL // Empty define
#define GLLITE_GL_LIST_WIN32 // Empty define
#endif // __linux__


#if defined(_WIN32)

#define GLDECL WINAPI

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define GL_ARRAY_BUFFER                   0x8892 // Acquired from:
#define GL_ARRAY_BUFFER_BINDING           0x8894 // https://www.opengl.org/registry/api/GL/glext.h
#define GL_COLOR_ATTACHMENT0              0x8CE0
#define GL_COMPILE_STATUS                 0x8B81
#define GL_CURRENT_PROGRAM                0x8B8D
#define GL_DYNAMIC_DRAW                   0x88E8
#define GL_ELEMENT_ARRAY_BUFFER           0x8893
#define GL_ELEMENT_ARRAY_BUFFER_BINDING   0x8895
#define GL_FRAGMENT_SHADER                0x8B30
#define GL_FRAMEBUFFER                    0x8D40
#define GL_FRAMEBUFFER_COMPLETE           0x8CD5
#define GL_FUNC_ADD                       0x8006
#define GL_INVALID_FRAMEBUFFER_OPERATION  0x0506
#define GL_MAJOR_VERSION                  0x821B
#define GL_MINOR_VERSION                  0x821C
#define GL_STATIC_DRAW                    0x88E4
#define GL_STREAM_DRAW                    0x88E0
#define GL_TEXTURE0                       0x84C0
#define GL_VERTEX_SHADER                  0x8B31
#define GL_INFO_LOG_LENGTH                0x8B84
#define GL_LINK_STATUS                    0x8B82
#define GL_TEXTURE_2D					  0x0DE1
#define GL_ACTIVE_ATTRIBUTES			  0x8B89
#define GL_ACTIVE_UNIFORMS				  0x8B86
#define GL_CLAMP_TO_BORDER                0x812D
#define GL_RGBA32F                        0x8814
#define GL_RGB32F                         0x8815
#define GL_R32F                           0x822E
#define GL_R8							  0x8229
#define GL_RG32F                          0x8230
#define GL_RG                             0x8227
#define GL_RGBA32UI                       0x8D70
#define GL_R32UI                          0x8236
#define GL_RGBA_INTEGER                   0x8D99
#define GL_RED_INTEGER                    0x8D94
#define GL_CLAMP_VERTEX_COLOR_ARB         0x891A
#define GL_CLAMP_FRAGMENT_COLOR_ARB       0x891B
#define GL_CLAMP_READ_COLOR_ARB           0x891C
#define GL_PROGRAM_POINT_SIZE			  0x8642
#define GL_POINT_SPRITE					  0x8861
#define GL_INTERLEAVED_ATTRIBS            0x8C8C
#define GL_SEPARATE_ATTRIBS               0x8C8D
#define GL_TRANSFORM_FEEDBACK_BUFFER      0x8C8E
#define GL_RASTERIZER_DISCARD             0x8C89 

typedef char GLchar;
typedef ptrdiff_t GLintptr;
typedef ptrdiff_t GLsizeiptr;

#define GLLITE_GL_LIST_WIN32 \
    /* ret, name, params */ \
    GLE(void,      BlendEquation,           GLenum mode) \
    GLE(void,      ActiveTexture,           GLenum texture) \
    /* end */

#endif // _WIN32

#include <GL/gl.h>


#define GLLITE_GL_LIST \
    /* ret, name, params */ \
    GLE(void,      AttachShader,            GLuint program, GLuint shader) \
    GLE(void,      BindBuffer,              GLenum target, GLuint buffer) \
    GLE(void,      BindFramebuffer,         GLenum target, GLuint framebuffer) \
	GLE(void,	   BindAttribLocation,		GLuint program,GLuint index,const GLchar *name)\
    GLE(void,      BufferData,              GLenum target, GLsizeiptr size, const GLvoid *data, GLenum usage) \
    GLE(void,      BufferSubData,           GLenum target, GLintptr offset, GLsizeiptr size, const GLvoid * data) \
    GLE(GLenum,    CheckFramebufferStatus,  GLenum target) \
    GLE(void,      ClearBufferfv,           GLenum buffer, GLint drawbuffer, const GLfloat * value) \
    GLE(void,      CompileShader,           GLuint shader) \
    GLE(GLuint,    CreateProgram,           void) \
    GLE(GLuint,    CreateShader,            GLenum type) \
    GLE(void,      DeleteBuffers,           GLsizei n, const GLuint *buffers) \
    GLE(void,      DeleteFramebuffers,      GLsizei n, const GLuint *framebuffers) \
	GLE(void,      DeleteProgram,           GLuint program)\
	GLE(void,      DeleteShader,            GLuint shader)\
    GLE(void,      EnableVertexAttribArray, GLuint index) \
	GLE(void,      DisableVertexAttribArray,GLuint index) \
    GLE(void,      DrawBuffers,             GLsizei n, const GLenum *bufs) \
    GLE(void,      FramebufferTexture2D,    GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) \
    GLE(void,      GenBuffers,              GLsizei n, GLuint *buffers) \
    GLE(void,      GenFramebuffers,         GLsizei n, GLuint * framebuffers) \
    GLE(GLint,     GetAttribLocation,       GLuint program, const GLchar *name) \
    GLE(void,      GetShaderInfoLog,        GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog) \
	GLE(void,      GetProgramInfoLog,       GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog) \
    GLE(void,      GetShaderiv,             GLuint shader, GLenum pname, GLint *params) \
	GLE(void,      GetProgramiv,            GLuint program, GLenum pname, GLint *params) \
    GLE(GLint,     GetUniformLocation,      GLuint program, const GLchar *name) \
    GLE(void,      LinkProgram,             GLuint program) \
    GLE(void,      ShaderSource,            GLuint shader, GLsizei count, const GLchar* const *string, const GLint *length) \
    GLE(void,      Uniform1i,               GLint location, GLint v0) \
	GLE(void,      Uniform2i,               GLint location, GLint v0, GLint v1) \
	GLE(void,      Uniform3i,               GLint location, GLint v0, GLint v1, GLint v2) \
	GLE(void,      Uniform4i,               GLint location, GLint v0, GLint v1, GLint v2, GLint v3) \
    GLE(void,      Uniform1f,               GLint location, GLfloat v0) \
    GLE(void,      Uniform2f,               GLint location, GLfloat v0, GLfloat v1) \
	GLE(void,      Uniform3f,               GLint location, GLfloat v0, GLfloat v1, GLfloat v3) \
    GLE(void,      Uniform4f,               GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) \
    GLE(void,      UniformMatrix4fv,        GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) \
    GLE(void,      UseProgram,              GLuint program) \
    GLE(void,      VertexAttribPointer,     GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid * pointer) \
    GLE(void,      VertexAttribIPointer,    GLuint index, GLint size, GLenum type, GLsizei stride, const GLvoid * pointer) \
	GLE(void,	   GetActiveAttrib,			GLuint program, GLuint index,GLsizei bufSize, GLsizei * length, GLint * size, GLenum * type, GLchar * name)\
	GLE(void,	   GetActiveUniform,		GLuint program, GLuint index,GLsizei bufSize, GLsizei * length, GLint * size, GLenum * type, GLchar * name)\
	GLE(void,	   FramebufferTexture,		GLenum target,GLenum attachment,GLuint texture,GLint level)\
	GLE(void,	   Enablei,					GLenum cap, GLuint index)\
	GLE(void,	   Disablei,				GLenum cap, GLuint index)\
	GLE(void,      ClampColorARB,			GLenum target,GLenum clamp)\
    GLE(void,      TransformFeedbackVaryings, GLuint program, GLsizei count, const char** varyings,GLenum bufferMode)\
    GLE(void,      BindBufferBase,          GLenum target,GLuint index,GLuint buffer)\
    GLE(void,      BeginTransformFeedback,	GLenum primitiveMode)\
    GLE(void,      EndTransformFeedback,	void)\
    GLE(void,      GetBufferSubData,        GLenum target, GLintptr offset, GLsizeiptr size,void * data )\
    GLE(void,      GetNamedBufferSubData,   GLuint buffer, GLintptr offset, GLsizeiptr size,void * data )\
    GLE(void,      GetnTexImage,            GLenum traget, GLint level,GLenum format,GLenum type,GLsizei bufsize, void* data)\
    /* end */
//GLE(void, DeleteTextures, GLsizei count, const GLuint * textures)
//GLE(void, GetTexImage, GLenum target, GLint level, GLenum format, GLenum type, GLvoid * img)
#define GLE(ret, name, ...) typedef ret GLDECL name##proc(__VA_ARGS__); extern name##proc * gl##name;
GLLITE_GL_LIST
GLLITE_GL_LIST_WIN32
#undef GLE

bool gl_lite_init();
#define GL_TRAP if (auto err = glGetError() ) { printf("GlError:%d (%x)\n", err,err); __debugbreak(); }
#endif //GL_LITE_H

// =============================================================================

#ifdef GL_LITE_IMPLEMENTATION

#define GLE(ret, name, ...) name##proc * gl##name;
GLLITE_GL_LIST
GLLITE_GL_LIST_WIN32
#undef GLE

bool gl_lite_init();

#if defined(__linux__)
bool gl_lite_init()
{
	void* libGL = dlopen("libGL.so", RTLD_LAZY);
	if (!libGL) {
		printf("ERROR: libGL.so couldn't be loaded\n");
		return false;
	}

#define GLE(ret, name, ...)                                                    \
            gl##name = (name##proc *) dlsym(libGL, "gl" #name);                    \
            if (!gl##name) {                                                       \
                printf("Function gl" #name " couldn't be loaded from libGL.so\n"); \
                return false;                                                      \
            }
	GLLITE_GL_LIST
#undef GLE
	return true;
}
#elif defined(_WIN32)



	extern "C" PROC WINAPI wglGetProcAddress(LPCSTR lpszProc);
bool gl_lite_init()
{
	/*HINSTANCE dll = LoadLibraryA("opengl32.dll");
	typedef PROC WINAPI wglGetProcAddressproc(LPCSTR lpszProc);
	if (!dll) {
		OutputDebugStringA("opengl32.dll not found.\n");
		return false;
	}
	wglGetProcAddressproc* wglGetProcAddress =
		(wglGetProcAddressproc*)GetProcAddress(dll, "wglGetProcAddress");*/

#define GLE(ret, name, ...)                                                                    \
            gl##name = (name##proc *)wglGetProcAddress("gl" #name);                                \
            if (!gl##name) {                                                                       \
                OutputDebugStringA("Function gl" #name " couldn't be loaded from opengl32.dll\n"); \
                return false;                                                                      \
            }
	GLLITE_GL_LIST
		GLLITE_GL_LIST_WIN32
#undef GLE
		return true;
}
#else
#error "GL loading for this platform is not implemented yet."
#endif


#endif //GL_LITE_IMPLEMENTATION
