/*
* cl_lite - single header minimal opencl includes
*/
/*
*   TODO: other os'es
*/
#ifndef CL_LITE_H_INCLUDED
#define CL_LITE_H_INCLUDED

#include <stdint.h>

/*

typedef int8_t          cl_char;
typedef uint8_t         cl_uchar;
typedef int16_t         cl_short;
typedef uint16_t        cl_ushort;
typedef int32_t         cl_int;
typedef uint32_t        cl_uint;
typedef int64_t         cl_long;
typedef uint64_t        cl_ulong;

typedef uint16_t        cl_half;
typedef float           cl_float;
typedef double          cl_double;

*/

#define CL_DEVICE_TYPE_DEFAULT                      (1 << 0)
#define CL_DEVICE_TYPE_CPU                          (1 << 1)
#define CL_DEVICE_TYPE_GPU                          (1 << 2)
#define CL_DEVICE_TYPE_ACCELERATOR                  (1 << 3)

#define CL_PROGRAM_BUILD_LOG                        0x1183

#define CL_DECL __stdcall

#define CL_TYPE_LIST\
    CL_TYPE(platform_id)\
    CL_TYPE(device_id)\
    CL_TYPE(context)\
    CL_TYPE(command_queue)\
    CL_TYPE(mem)\
    CL_TYPE(program)\
    CL_TYPE(kernel)\
    CL_TYPE(event)\
    CL_TYPE(samepler)

#define CL_TYPE(name) typedef struct _cl_ ## name * cl_ ## name;
CL_TYPE_LIST
#undef CL_TYPE
#define CLLITE_CL_LIST \
    CLE(int32_t,    clGetPlatformIDs, uint32_t num_entries, cl_platform_id* platforms,uint32_t* num_platforms) \
    CLE(int32_t,    clGetDeviceIDs,   cl_platform_id platform, uint64_t device_type, uint32_t num_entries, cl_device_id* devices, uint32_t* num_devices) \
    CLE(cl_program, clCreateProgramWithSource, cl_context context, uint32_t count,const char** strings,const size_t *lengths,int32_t *errcode_ret) \
    CLE(int32_t,    clBuildProgram,cl_program program,uint32_t num_devices,const cl_device_id* devices,const char* options,void*,void*) \
    CLE(int32_t,    clGetProgramBuildInfo,cl_program program, cl_device_id device, uint32_t param_name,size_t param_value_size, void* param_value,size_t* param_value_size_ret)\
    CLE(cl_kernel,  clCreateKernel,cl_program program,const char* kernel_name,int32_t * errcode_ret)\
    CLE(cl_context, clCreateContext, const int32_t** properties,uint32_t num_devices,const cl_device_id* devices,void* callback,void* user_data,int32_t* errcode_ret) \
    CLE(int32_t,    clReleaseContext,cl_context context)\
    CLE(int32_t,    clReleaseCommandQueue,cl_command_queue command_queue)\
    CLE(int32_t,    clReleaseMemObject,cl_mem memobj)\
    CLE(int32_t,    clReleaseProgram,cl_program program)\
    CLE(int32_t,    clReleaseKernel,cl_kernel kernel)\
    CLE(cl_command_queue,clCreateCommandQueueWithProperties, cl_context context,cl_device_id device,const int32_t** properties,int32_t* errcode_ret)\
    CLE(int32_t,    clSetKernelArg,cl_kernel kernel,uint32_t arg_index,size_t arg_size,const void* arg_value)\


#define CLE(ret, name, ...) typedef ret CL_DECL name##proc(__VA_ARGS__);name##proc * name;
CLLITE_CL_LIST
#undef CLE

#endif

#ifdef CL_LITE_IMPLEMENTATION

typedef void* PVOID;
typedef PVOID HANDLE;

typedef HANDLE HMODULE;

extern "C" void* __stdcall GetProcAddress(HMODULE,const char*);
extern "C" void* __stdcall LoadLibraryA(const char*);
extern "C" void* __stdcall OutputDebugStringA(const char*);

void* load_function(HMODULE module,const char* function_name)
{

    return GetProcAddress(module, function_name);
}
bool cl_lite_init()
{
    HMODULE cl_module = LoadLibraryA("opencl.dll");

#define CLE(ret, name, ...)                                                                    \
            name = (name##proc *)load_function(cl_module,#name);                           \
            if (!name) {                                                                       \
                OutputDebugStringA("Function " #name " couldn't be loaded from opencl.dll\n"); \
                return false;                                                                  \
            }
    CLLITE_CL_LIST
    
#undef CLE
        return true;
}
#endif