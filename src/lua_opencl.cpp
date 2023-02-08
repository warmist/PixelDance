#include "lua_opencl.h"

#define CL_LITE_IMPLEMENTATION
#include "cl_lite.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"
static cl_device_id device;
static cl_context context;

int lua_build_program(lua_State* L)
{
    program=clCreateProgramWithSource(context, 1, source, source_size, &err);
    if (err < 0)
    {

    }
    err=clBuildProgram(program, 0, nullptr, nullptr, nullptr, nullptr);
    if (err < 0)
    {

    }
    kernel = clCreateKernel(program, KERNEL_FUNC, &err);

    //add set kernel arg

}
int lua_create_buffer(lua_State* L)
{
    //clEnqueueWriteBuffer
    //clEnqueueReadBuffer
    //https://registry.khronos.org/OpenCL/sdk/2.2/docs/man/html/clCreateFromGLTexture.html

}
static const luaL_Reg lua_opencl_lib[] = {
    { "build_program",lua_build_program},
    { "create_buffer",lua_create_buffer},

    { NULL, NULL }
};

int lua_open_opencl(lua_State* L)
{
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

    luaL_newlib(L, lua_opencl_lib);
    lua_setglobal(L, "opencl");

    return 0;
}