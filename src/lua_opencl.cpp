#include "lua_opencl.h"

#define CL_LITE_IMPLEMENTATION
#include "cl_lite.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"
static cl_device_id device;
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
    return 0;
}