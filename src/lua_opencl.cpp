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

static cl_kernel* check_kernel(lua_State* L, int id) { return reinterpret_cast<cl_kernel*>(luaL_checkudata(L, id, "cl_kernel")); }

static cl_mem* check_mem(lua_State* L, int id) { return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem")); }
static cl_mem* check_mem_gl(lua_State* L, int id) { return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem_gl")); }
static cl_mem* check_mem_any(lua_State* L, int id) { 
    //TODO: better error messages!
    if(luaL_testudata(L,id,"cl_mem"))
        return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem"));
    else
        return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem_gl"));
}
static cl_mem* test_mem_any(lua_State* L, int id) {
    //TODO: better error messages!
    if (luaL_testudata(L, id, "cl_mem"))
        return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem"));
    else if(luaL_testudata(L, id, "cl_mem_gl"))
        return reinterpret_cast<cl_mem*>(luaL_checkudata(L, id, "cl_mem_gl"));
    return nullptr;
}
static void* check_luajit_pointer(lua_State* L, int id) { //not actually a check as it does not error out!
    if((lua_type(L, 3) == 10) /*cdata*/ || (lua_type(L, 3) == LUA_TLIGHTUSERDATA))
    {
        return (void*)lua_topointer(L, 3); //TODO: check pointer?
    }
    return nullptr;
}
int del_kernel(lua_State* L)
{
    auto k = check_kernel(L, 1);
    clReleaseKernel(*k);
    return 0;
}
int del_buffer(lua_State* L)
{
    auto k = check_mem_any(L, 1);
    clReleaseMemObject(*k);
    return 0;
}

void get_from_lua(lua_State* L, std::vector<float>& data, int arg_offset, int num_args)
{
    data.resize(num_args);
    for (int i = 0; i < num_args; i++)
    {
        data[i] = luaL_checknumber(L, i + arg_offset);
    }
}
void get_from_lua(lua_State* L, std::vector<int>& data, int arg_offset, int num_args)
{
    data.resize(num_args);
    for (int i = 0; i < num_args; i++)
    {
        data[i] = luaL_checkinteger(L, i + arg_offset);
    }
}

template<typename T>
static int set_kernel_arg(lua_State* L)
{
    auto kernel = check_kernel(L, 1);
    auto uloc = luaL_checkint(L, 2);

    if (auto data = check_luajit_pointer(L, 3))
    {
        auto err=clSetKernelArg(*kernel, uloc, sizeof(void*), data);
        if (err)
        {
            luaL_error(L, "Failed to set kernel arg :%d", err);
        }
    }
    else if (auto mem= test_mem_any(L, 3))
    {
        auto err = clSetKernelArg(*kernel, uloc, sizeof(cl_mem), mem);
        if (err)
        {
            luaL_error(L, "Failed to set kernel arg :%d", err);
        }
    }
    else
    {
        const int arg_offset = 2;
        int num_args = lua_gettop(L) - arg_offset;
        if (num_args < 1)
            luaL_error(L, "invalid count of arguments: %d", num_args);

        std::vector<T> tmp_array(num_args);

        //TODO: switch by T to fill the array...
        //something like get_from_lua<T>(tmp_array,L,arg_offset,num_args);
        get_from_lua(L, tmp_array, arg_offset, num_args);
        auto err = clSetKernelArg(*kernel, uloc, sizeof(T) * num_args, tmp_array.data());
        if (err)
        {
            luaL_error(L, "Failed to set kernel arg :%d", err);
        }
    }
    return 0;
}
int lua_run_kernel(lua_State* L)
{
    auto kernel = check_kernel(L, 1);
    
    size_t local_size, global_size;
    auto err = clGetKernelWorkGroupInfo(*kernel, device, CL_KERNEL_WORK_GROUP_SIZE, sizeof(local_size), &local_size, NULL);
    if (err)
    {
        luaL_error(L, "Failed to get kernel info:%d", err);
    }
    
    size_t count = luaL_checkinteger(L, 2);
    /*
    * TODO: multi coord
    const int arg_offset = 2;
    int num_args = lua_gettop(L) - arg_offset;
    std::vector<int> global_sizes; 
    global_sizes.resize(num_args);
    int total_count = 1;
    for (int i = arg_offset; i < num_args;i++)
    {
        size_t count = luaL_checkinteger(L, i);
        global_sizes[i - arg_offset] = count;
        total_count *= count;
    }*/
    // Number of total work items - localSize must be devisor
    global_size = ceil(count / (float)local_size) * local_size;
    err=clEnqueueNDRangeKernel(queue, *kernel, 1, NULL, &global_size, &local_size, 0, NULL, NULL);
    if (err)
    {
        luaL_error(L, "Failed to get kernel info:%d", err);
    }
    clFinish(queue);//TODO optional?
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
    err=clBuildProgram(program, 0, nullptr, "-w", nullptr, nullptr);
   
    size_t log_size;
    clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG, 0, NULL, &log_size);
    std::vector<char> buffer(log_size+1);
    clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG,log_size + 1, buffer.data(), NULL);
    for (auto& c : buffer)
        if (c == 0)
            c = '\n';
    buffer.back() = 0;
    printf("Build info:%s", buffer.data());
    if (err < 0)
    {
        luaL_error(L, "Failed to build cl program(%d)\nerror:%s",err, buffer.data());
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

            lua_pushcfunction(L, set_kernel_arg<int>);
            lua_setfield(L, -2, "seti");

            lua_pushcfunction(L, lua_run_kernel);
            lua_setfield(L, -2, "run");

            lua_pushvalue(L, -1);
            lua_setfield(L, -2, "__index");
        }
        lua_setmetatable(L, -2);
    }
    return kernels.size();
}
int set_buffer(lua_State* L)
{
    //TODO: maybe non blocking?
    auto buf = check_mem(L, 1);
    size_t size = luaL_checkinteger(L, 2);
    void* data= check_luajit_pointer(L, 3);
    if(!data)
    {
        luaL_argerror(L, 3, "not a data pointer");
    }
    size_t offset = luaL_optinteger(L, 4, 0);
    clEnqueueWriteBuffer(queue, *buf, true, offset, size, data, 0, nullptr, nullptr);
    return 0;
}
int get_buffer(lua_State* L)
{
    auto buf = check_mem(L, 1);
    size_t size = luaL_checkinteger(L, 2);
    void* data;
    if ((lua_type(L, 3) == 10) /*cdata*/ || (lua_type(L, 3) == LUA_TLIGHTUSERDATA))
    {
        data = (void*)lua_topointer(L, 3); //TODO: check pointer?
    }
    else
    {
        luaL_argerror(L, 3, "not a data pointer");
    }
    size_t offset = luaL_optinteger(L, 4, 0);
    clEnqueueReadBuffer(queue, *buf, true, offset, size, data, 0, nullptr, nullptr);
    return 0;
}
//HACK:
struct gl_texture {
    unsigned int id;
};
#define GL_TEXTURE_2D					  0x0DE1
//
int lua_aquire(lua_State* L)
{
    auto mem = check_mem_gl(L, 1);
    auto err=clEnqueueAcquireGLObjects(queue, 1, mem, 0, nullptr, nullptr);
    if (err < 0)
    {
        luaL_error(L, "Failed to aquire opengl objects:%d", err);
    }
    return 0;
}
int lua_release(lua_State* L)
{
    auto mem = check_mem_gl(L, 1);
    auto err = clEnqueueReleaseGLObjects(queue, 1, mem, 0, nullptr, nullptr);
    if (err < 0)
    {
        luaL_error(L, "Failed to release opengl objects:%d", err);
    }
    return 0;
}
int lua_create_buffer_gl(lua_State* L)
{
    int32_t err;
    //create from:
    // opengl buffer
    // texture + //https://registry.khronos.org/OpenCL/sdk/2.2/docs/man/html/clCreateFromGLTexture.html
    unsigned int tex_id = 0;
    if (auto tex = luaL_checkudata(L, 1, "texture"))
    {
        auto t = *(gl_texture**)tex;
        tex_id = t->id;
    }
    int flags = CL_MEM_READ_WRITE; //TODO optionally no read/write?
    cl_mem buffer;
    buffer = clCreateFromGLTexture(context, flags, GL_TEXTURE_2D, 0, tex_id, &err);
    if (err < 0)
    {
        luaL_error(L, "Failed to create opencl buffer:%d", err);
    }
    auto np = (cl_mem*)lua_newuserdata(L, sizeof(cl_mem));
    *np = buffer;
    if (luaL_newmetatable(L, "cl_mem_gl"))
    {
        lua_pushcfunction(L, del_buffer);
        lua_setfield(L, -2, "__gc");

        lua_pushcfunction(L, set_buffer);
        lua_setfield(L, -2, "set");

        lua_pushcfunction(L, get_buffer);
        lua_setfield(L, -2, "get");
        
        lua_pushcfunction(L, lua_aquire);
        lua_setfield(L, -2, "aquire");

        lua_pushcfunction(L, lua_release);
        lua_setfield(L, -2, "release");

        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);

    return 1;
}
int lua_create_buffer(lua_State* L)
{
    size_t size = luaL_checkinteger(L, 1);

    int32_t err;
    void* data = nullptr;
    //create from:
    // buffer +
    // array?
    if ((lua_type(L, 2) == 10) /*cdata*/ || (lua_type(L, 2) == LUA_TLIGHTUSERDATA))
    {
        data = (void*)lua_topointer(L, 2); //TODO: check pointer?
    }
    int flags = CL_MEM_READ_WRITE;
    if (data)
    {
        flags |= CL_MEM_COPY_HOST_PTR;
    }
    cl_mem buffer = clCreateBuffer(context, flags, size, data, &err);
    if (err < 0)
    {
        luaL_error(L, "Failed to create opencl buffer:%d", err);
    }
    auto np = (cl_mem*)lua_newuserdata(L, sizeof(cl_mem));
    *np = buffer;
    if (luaL_newmetatable(L, "cl_mem"))
    {
        lua_pushcfunction(L, del_buffer);
        lua_setfield(L, -2, "__gc");

        lua_pushcfunction(L, set_buffer);
        lua_setfield(L, -2, "set");

        lua_pushcfunction(L, get_buffer);
        lua_setfield(L, -2, "get");

        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    
    return 1;
}
static const luaL_Reg lua_opencl_lib[] = {
    { "make_program",lua_build_program},
    { "make_buffer",lua_create_buffer},
    { "make_buffer_gl",lua_create_buffer_gl},

    { NULL, NULL }
};

void cleanup()
{
    //clReleaseContext(context);
    //clReleaseCommandQueue(queue);
}
extern "C" void* wglGetCurrentContext();
extern "C" void* wglGetCurrentDC();
int lua_open_opencl(lua_State* L)
{
    //TODO: do not reinit cl_lite, some way to retain context (e.g. for some nice buffer sharing)
    if (!init_done)
    {
        //    cleanup();
        if (!cl_lite_init())
        {
            luaL_error(L, "Failed to init cl_lite");
            return 0;
        }
        cl_platform_id platform;
        int err = clGetPlatformIDs(1, &platform, nullptr);
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
            luaL_error(L, "Couldn't access any devices");
        }
        const intptr_t properties[] = {
            CL_CONTEXT_PLATFORM,(intptr_t)platform,
            CL_GL_CONTEXT_KHR, (intptr_t)wglGetCurrentContext(),
            CL_WGL_HDC_KHR, (intptr_t)wglGetCurrentDC(),
            0
        };
        //TODO: this needs to pass in opengl context sharing
        context = clCreateContext(properties, 1, &device, NULL, NULL, &err);
        if (err < 0) {
            luaL_error(L, "Couldn't create context");
        }
        queue = clCreateCommandQueueWithProperties(context, device, NULL, &err);
        if (err < 0) {
            luaL_error(L, "Couldn't create command queue");
        }
        init_done = true;
    }
    luaL_newlib(L, lua_opencl_lib);
    lua_setglobal(L, "opencl");

    return 0;
}