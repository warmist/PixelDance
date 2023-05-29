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

typedef cl_uint             cl_bool;                     // WARNING!  Unlike cl_ types in cl_platform.h, cl_bool is not guaranteed to be the same size as the bool in kernels.
typedef cl_ulong            cl_bitfield;
typedef cl_ulong            cl_properties;
typedef cl_bitfield         cl_device_type;
typedef cl_uint             cl_platform_info;
typedef cl_uint             cl_device_info;
typedef cl_bitfield         cl_device_fp_config;
typedef cl_uint             cl_device_mem_cache_type;
typedef cl_uint             cl_device_local_mem_type;
typedef cl_bitfield         cl_device_exec_capabilities;

*/

#define CL_DEVICE_TYPE_DEFAULT                      (1 << 0)
#define CL_DEVICE_TYPE_CPU                          (1 << 1)
#define CL_DEVICE_TYPE_GPU                          (1 << 2)
#define CL_DEVICE_TYPE_ACCELERATOR                  (1 << 3)

#define CL_PROGRAM_BUILD_LOG                        0x1183

#define CL_MEM_READ_WRITE                           (1 << 0)
#define CL_MEM_WRITE_ONLY                           (1 << 1)
#define CL_MEM_READ_ONLY                            (1 << 2)
#define CL_MEM_USE_HOST_PTR                         (1 << 3)
#define CL_MEM_ALLOC_HOST_PTR                       (1 << 4)
#define CL_MEM_COPY_HOST_PTR                        (1 << 5)

#define CL_KERNEL_WORK_GROUP_SIZE                   0x11B0
#define CL_KERNEL_COMPILE_WORK_GROUP_SIZE           0x11B1
#define CL_KERNEL_LOCAL_MEM_SIZE                    0x11B2
#define CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE 0x11B3
#define CL_KERNEL_PRIVATE_MEM_SIZE                  0x11B4
#define CL_KERNEL_GLOBAL_WORK_SIZE                  0x11B5


#define CL_CONTEXT_PLATFORM                         0x1084

//CL opengl extension
//https://registry.khronos.org/OpenCL/sdk/2.2/docs/man/html/clCreateFromGLBuffer.html
#define CL_GL_OBJECT_BUFFER                     0x2000
#define CL_GL_OBJECT_TEXTURE2D                  0x2001
#define CL_GL_OBJECT_TEXTURE3D                  0x2002
#define CL_GL_OBJECT_RENDERBUFFER               0x2003

#define CL_GL_OBJECT_TEXTURE2D_ARRAY            0x200E
#define CL_GL_OBJECT_TEXTURE1D                  0x200F
#define CL_GL_OBJECT_TEXTURE1D_ARRAY            0x2010
#define CL_GL_OBJECT_TEXTURE_BUFFER             0x2011

#define CL_GL_CONTEXT_KHR                       0x2008
#define CL_WGL_HDC_KHR                          0x200B


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
    CLE(int32_t,    clCreateKernelsInProgram,cl_program program,uint32_t num_kernels,cl_kernel* kernels,uint32_t* num_kernels_ret)\
    CLE(cl_context, clCreateContext, const intptr_t* properties,uint32_t num_devices,const cl_device_id* devices,void* callback,void* user_data,int32_t* errcode_ret) \
    CLE(int32_t,    clReleaseContext,cl_context context)\
    CLE(int32_t,    clReleaseCommandQueue,cl_command_queue command_queue)\
    CLE(int32_t,    clReleaseMemObject,cl_mem memobj)\
    CLE(int32_t,    clReleaseProgram,cl_program program)\
    CLE(int32_t,    clReleaseKernel,cl_kernel kernel)\
    CLE(cl_command_queue,clCreateCommandQueueWithProperties, cl_context context,cl_device_id device,const int32_t** properties,int32_t* errcode_ret)\
    CLE(int32_t,    clSetKernelArg,cl_kernel kernel,uint32_t arg_index,size_t arg_size,const void* arg_value)\
    CLE(cl_mem,     clCreateBuffer,cl_context context,uint64_t flags,size_t size,void* host_ptr,int32_t* errcode_ret)\
    CLE(int32_t,    clEnqueueWriteBuffer,cl_command_queue command_queue,cl_mem buffer,uint32_t blocking_write,size_t offset,size_t size,\
                const void* ptr,uint32_t num_events_in_wait_list, const cl_event* event_wait_list,cl_event* event)\
    CLE(int32_t,    clEnqueueReadBuffer,cl_command_queue command_queue,cl_mem buffer,uint32_t blocking_read,size_t offset,size_t size,\
                void* ptr,uint32_t num_events_in_wait_list,const cl_event* event_wait_list,cl_event* event)\
    CLE(int32_t,    clEnqueueFillBuffer,cl_command_queue command_queue, cl_mem  buffer, const void* pattern,size_t  pattern_size, size_t  offset, size_t  size, \
                uint32_t num_events_in_wait_list,const cl_event* event_wait_list, cl_event* event)\
    CLE(int32_t,    clGetKernelWorkGroupInfo,cl_kernel kernel,cl_device_id device,uint32_t param_name,\
                size_t param_value_size,void* param_value,size_t* param_value_size_ret)\
    CLE(int32_t,    clEnqueueNDRangeKernel,cl_command_queue command_queue,cl_kernel kernel,uint32_t work_dim,const size_t* global_work_offset,\
                const size_t* global_work_size,const size_t* local_work_size,uint32_t num_events_in_wait_list,const cl_event* event_wait_list,\
                cl_event* event)\
    CLE(int32_t,    clFinish,cl_command_queue command_queue)\
    CLE(cl_mem, clCreateFromGLBuffer,cl_context context,uint32_t flags, unsigned int bufob, int32_t* errcode_ret)\
    CLE(cl_mem, clCreateFromGLTexture,cl_context context,uint32_t flags,unsigned int target,int miplevel,unsigned int texture,int32_t* errcode_ret)\
    CLE(int32_t, clEnqueueAcquireGLObjects, cl_command_queue command_queue,uint32_t num_objects,const cl_mem* mem_objects,uint32_t num_events_in_wait_list,const cl_event* event_wait_list,cl_event* event)\
    CLE(int32_t, clEnqueueReleaseGLObjects, cl_command_queue command_queue,uint32_t num_objects,const cl_mem* mem_objects,uint32_t num_events_in_wait_list,const cl_event* event_wait_list,cl_event* event)

#define CLE(ret, name, ...) typedef ret CL_DECL name##proc(__VA_ARGS__);name##proc * name;
CLLITE_CL_LIST
#undef CLE
const char* cl_get_error_string(int error_code);
#endif

#ifdef CL_LITE_IMPLEMENTATION

typedef void* PVOID;
typedef PVOID HANDLE;

typedef HANDLE HMODULE;

extern "C" void* __stdcall GetProcAddress(HMODULE,const char*);
extern "C" void* __stdcall LoadLibraryA(const char*);
extern "C" void* __stdcall OutputDebugStringA(const char*); //TODO: remove this

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
const char* cl_get_error_string(int error_code){
    switch (error_code) {
    case 0: return "CL_SUCCESS";
    case -1: return "CL_DEVICE_NOT_FOUND";
    case -2: return "CL_DEVICE_NOT_AVAILABLE";
    case -3: return "CL_COMPILER_NOT_AVAILABLE";
    case -4: return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
    case -5: return "CL_OUT_OF_RESOURCES";
    case -6: return "CL_OUT_OF_HOST_MEMORY";
    case -7: return "CL_PROFILING_INFO_NOT_AVAILABLE";
    case -8: return "CL_MEM_COPY_OVERLAP";
    case -9: return "CL_IMAGE_FORMAT_MISMATCH";
    case -10: return "CL_IMAGE_FORMAT_NOT_SUPPORTED";
    case -12: return "CL_MAP_FAILURE";
    case -13: return "CL_MISALIGNED_SUB_BUFFER_OFFSET";
    case -14: return "CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST";
    case -15: return "CL_COMPILE_PROGRAM_FAILURE";
    case -16: return "CL_LINKER_NOT_AVAILABLE";
    case -17: return "CL_LINK_PROGRAM_FAILURE";
    case -18: return "CL_DEVICE_PARTITION_FAILED";
    case -19: return "CL_KERNEL_ARG_INFO_NOT_AVAILABLE";
    case -30: return "CL_INVALID_VALUE";
    case -31: return "CL_INVALID_DEVICE_TYPE";
    case -32: return "CL_INVALID_PLATFORM";
    case -33: return "CL_INVALID_DEVICE";
    case -34: return "CL_INVALID_CONTEXT";
    case -35: return "CL_INVALID_QUEUE_PROPERTIES";
    case -36: return "CL_INVALID_COMMAND_QUEUE";
    case -37: return "CL_INVALID_HOST_PTR";
    case -38: return "CL_INVALID_MEM_OBJECT";
    case -39: return "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR";
    case -40: return "CL_INVALID_IMAGE_SIZE";
    case -41: return "CL_INVALID_SAMPLER";
    case -42: return "CL_INVALID_BINARY";
    case -43: return "CL_INVALID_BUILD_OPTIONS";
    case -44: return "CL_INVALID_PROGRAM";
    case -45: return "CL_INVALID_PROGRAM_EXECUTABLE";
    case -46: return "CL_INVALID_KERNEL_NAME";
    case -47: return "CL_INVALID_KERNEL_DEFINITION";
    case -48: return "CL_INVALID_KERNEL";
    case -49: return "CL_INVALID_ARG_INDEX";
    case -50: return "CL_INVALID_ARG_VALUE";
    case -51: return "CL_INVALID_ARG_SIZE";
    case -52: return "CL_INVALID_KERNEL_ARGS";
    case -53: return "CL_INVALID_WORK_DIMENSION";
    case -54: return "CL_INVALID_WORK_GROUP_SIZE";
    case -55: return "CL_INVALID_WORK_ITEM_SIZE";
    case -56: return "CL_INVALID_GLOBAL_OFFSET";
    case -57: return "CL_INVALID_EVENT_WAIT_LIST";
    case -58: return "CL_INVALID_EVENT";
    case -59: return "CL_INVALID_OPERATION";
    case -60: return "CL_INVALID_GL_OBJECT";
    case -61: return "CL_INVALID_BUFFER_SIZE";
    case -62: return "CL_INVALID_MIP_LEVEL";
    case -63: return "CL_INVALID_GLOBAL_WORK_SIZE";
    case -64: return "CL_INVALID_PROPERTY";
    case -65: return "CL_INVALID_IMAGE_DESCRIPTOR";
    case -66: return "CL_INVALID_COMPILER_OPTIONS";
    case -67: return "CL_INVALID_LINKER_OPTIONS";
    case -68: return "CL_INVALID_DEVICE_PARTITION_COUNT";
    case -69: return "CL_INVALID_PIPE_SIZE";
    case -70: return "CL_INVALID_DEVICE_QUEUE";
    case -71: return "CL_INVALID_SPEC_ID";
    case -72: return "CL_MAX_SIZE_RESTRICTION_EXCEEDED";
    case -1002: return "CL_INVALID_D3D10_DEVICE_KHR";
    case -1003: return "CL_INVALID_D3D10_RESOURCE_KHR";
    case -1004: return "CL_D3D10_RESOURCE_ALREADY_ACQUIRED_KHR";
    case -1005: return "CL_D3D10_RESOURCE_NOT_ACQUIRED_KHR";
    case -1006: return "CL_INVALID_D3D11_DEVICE_KHR";
    case -1007: return "CL_INVALID_D3D11_RESOURCE_KHR";
    case -1008: return "CL_D3D11_RESOURCE_ALREADY_ACQUIRED_KHR";
    case -1009: return "CL_D3D11_RESOURCE_NOT_ACQUIRED_KHR";
    case -1010: return "CL_INVALID_DX9_MEDIA_ADAPTER_KHR";
    case -1011: return "CL_INVALID_DX9_MEDIA_SURFACE_KHR";
    case -1012: return "CL_DX9_MEDIA_SURFACE_ALREADY_ACQUIRED_KHR";
    case -1013: return "CL_DX9_MEDIA_SURFACE_NOT_ACQUIRED_KHR";
    case -1093: return "CL_INVALID_EGL_OBJECT_KHR";
    case -1092: return "CL_EGL_RESOURCE_NOT_ACQUIRED_KHR";
    case -1001: return "CL_PLATFORM_NOT_FOUND_KHR";
    case -1057: return "CL_DEVICE_PARTITION_FAILED_EXT";
    case -1058: return "CL_INVALID_PARTITION_COUNT_EXT";
    case -1059: return "CL_INVALID_PARTITION_NAME_EXT";
    case -1094: return "CL_INVALID_ACCELERATOR_INTEL";
    case -1095: return "CL_INVALID_ACCELERATOR_TYPE_INTEL";
    case -1096: return "CL_INVALID_ACCELERATOR_DESCRIPTOR_INTEL";
    case -1097: return "CL_ACCELERATOR_TYPE_NOT_SUPPORTED_INTEL";
    case -1000: return "CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR";
    case -1098: return "CL_INVALID_VA_API_MEDIA_ADAPTER_INTEL";
    case -1099: return "CL_INVALID_VA_API_MEDIA_SURFACE_INTEL";
    case -1100: return "CL_VA_API_MEDIA_SURFACE_ALREADY_ACQUIRED_INTEL";
    case -1101: return "CL_VA_API_MEDIA_SURFACE_NOT_ACQUIRED_INTEL";
    default: return "CL_UNKNOWN_ERROR";
    }
}
#endif