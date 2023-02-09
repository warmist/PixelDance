#include "lua_opencl.h"

#define CL_LITE_IMPLEMENTATION
#include "cl_lite.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"
static cl_device_id device;
static cl_context context;
static cl_command_queue queue;

static bool init_done = false;
#include <vector>
/*
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
*/
static cl_kernel* check_kernel(lua_State* L, int id) { return reinterpret_cast<cl_kernel*>(luaL_checkudata(L, id, "cl_kernel")); }

int del_kernel(lua_State* L)
{
    auto k = check_kernel(L, 1);
    clReleaseKernel(*k);
    return 0;
}
//template<typename T>
//static void set_kernel_arg_inner(lua_State* L,cl_kernel k,uint32_t uloc, int arg_start, int num_args);
template<typename T>
static int set_kernel_arg(lua_State* L)
{
    auto kernel = check_kernel(L, 1);
    auto uloc = luaL_checkint(L, 2);

    const int arg_offset = 2;
    int num_args = lua_gettop(L) - arg_offset;
    if (num_args < 1)
        luaL_error(L, "invalid count of arguments: %d", num_args);
    std::vector<T> tmp_array(num_args);

    //TODO: switch by T to fill the array...
    //something like get_from_lua<T>(tmp_array,L,arg_offset,num_args);
    clSetKernelArg(*kernel, uloc, sizeof(T) * num_args, tmp_array.data());
    return 0;
}

int lua_build_program(lua_State* L)
{
    size_t source_len;
    const char* source= luaL_checklstring(L, 1,&source_len);
    int32_t err;
    cl_program program;
    program=clCreateProgramWithSource(context, 1, &source, &source_len, &err);
    if (err < 0)
    {
        luaL_error(L, "Failed to create cl program from source:%d", err);
    }
    err=clBuildProgram(program, 0, nullptr, nullptr, nullptr, nullptr);
    if (err < 0)
    {
        luaL_error(L, "Failed to build cl program:%d", err);
        size_t log_size;
        clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG, 0, NULL, &log_size);
        std::vector<char> buffer(log_size+1);
        clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG,log_size + 1, buffer.data(), NULL);
        luaL_error(L, "error:%s", buffer.data());
    }
    uint32_t num_kernels;
    err=clCreateKernelsInProgram(program, 0, NULL, &num_kernels);
    if (err < 0)
    {
        luaL_error(L, "Failed to create kernel(s):%d", err);
    }
    std::vector<cl_kernel> kernels(num_kernels);
    err = clCreateKernelsInProgram(program, num_kernels, kernels.data(), &num_kernels);
    if (err < 0)
    {
        luaL_error(L, "Failed to create kernel(s):%d", err);
    }
    clReleaseProgram(program);
    for (uint32_t i = 0; i < num_kernels; i++)
    {
        auto np = (cl_kernel*)lua_newuserdata(L, sizeof(cl_kernel));
        *np = kernels[i];

        if (luaL_newmetatable(L, "cl_kernel"))
        {
            lua_pushcfunction(L, del_kernel);
            lua_setfield(L, -2, "__gc");

            //TODO could be polymorphic from lua...
            lua_pushcfunction(L, set_kernel_arg<float>);
            lua_setfield(L, -2, "set");

            lua_pushvalue(L, -1);
            lua_setfield(L, -2, "__index");
        }
        lua_setmetatable(L, -2);
    }
    return kernels.size();
}
int lua_create_buffer(lua_State* L)
{
    //create from:
    // buffer
    // opengl buffer
    // texture
    // array?
    //clEnqueueWriteBuffer
    //clEnqueueReadBuffer
    //https://registry.khronos.org/OpenCL/sdk/2.2/docs/man/html/clCreateFromGLTexture.html
    return 0;
}
static const luaL_Reg lua_opencl_lib[] = {
    { "make_program",lua_build_program},
    { "create_buffer",lua_create_buffer},

    { NULL, NULL }
};

void cleanup()
{
    //clReleaseContext(context);
    //clReleaseCommandQueue(queue);
}
int lua_open_opencl(lua_State* L)
{
    //TODO: do not reinit cl_lite, some way to retain context (e.g. for some nice buffer sharing)
    if (init_done)
        return 0;
    //    cleanup();
    if (!cl_lite_init())
    {
        luaL_error(L, "Failed to init cl_lite");
        return 0;
    }
    cl_platform_id platform;
    int err=clGetPlatformIDs(1,&platform,nullptr);
    if (err < 0)
    {
        luaL_error(L, "Failed to get platform id");
        return 0;
    }
    //TODO: cpu fallback...
    err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, NULL);
    /*if (err == CL_DEVICE_NOT_FOUND) {
        // CPU
        err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_CPU, 1, &dev, NULL);
    }*/
    if (err < 0) {
        luaL_error(L,"Couldn't access any devices");
    }
    //TODO: this needs to pass in opengl context sharing
    context=clCreateContext(NULL, 1, &device, NULL, NULL, &err);
    if (err < 0) {
        luaL_error(L, "Couldn't create context");
    }
    queue = clCreateCommandQueueWithProperties(context, device, NULL, &err);
    if (err < 0) {
        luaL_error(L, "Couldn't create command queue");
    }
    luaL_newlib(L, lua_opencl_lib);
    lua_setglobal(L, "opencl");

    init_done = true;

    return 0;
}