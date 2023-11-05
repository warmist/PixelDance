#include "lua_vk.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

//#define VK_ENABLE_BETA_EXTENSIONS
#include "vulkan/vulkan.h"
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include "vulkan/vulkan_win32.h"

bool instance_inited = false; //TODO, maybe allow code to create new instance?
VkInstance instance;
VkDebugUtilsMessengerEXT debugMessenger;
VkPhysicalDevice physical_device = VK_NULL_HANDLE;
VkDevice device = VK_NULL_HANDLE;
VkSurfaceKHR surface=nullptr;
VkQueue basic_queue;
#define CHECK_OBJECT(obj)\
static obj* check_##obj(lua_State* L, int id) { return reinterpret_cast<obj*>(luaL_checkudata(L, id, #obj)); }

#include <vector>
#include <stdio.h>
//debug stuff
static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageType,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void* pUserData) {

    printf("Validataion layer:%s\n", pCallbackData->pMessage);

    return VK_FALSE;
}
VkResult CreateDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger) {
    auto func = (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    if (func != nullptr) {
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
    }
    else {
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}
void DestroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator) {
    auto func = (PFN_vkDestroyDebugUtilsMessengerEXT)vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
    if (func != nullptr) {
        func(instance, debugMessenger, pAllocator);
    }
}
//////////////////////////////////


std::vector<const char*> getRequiredExtensions()
{
    std::vector<const char*> ret;
    //TODO: sfml stuff should go here...
    ret.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    ret.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
    ret.push_back(VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
    //ret.push_back(VK_EXT_VIDEO_ENCODE_H264_EXTENSION_NAME); don't have this one ;((((
    return ret;
}
void print_extensions_instance()
{
    VkResult result;
    uint32_t count = 0;
    result = vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
    if (result != VK_SUCCESS) {
        return;
    }
    std::vector<VkExtensionProperties> extensionProperties(count);

    result = vkEnumerateInstanceExtensionProperties(nullptr, &count, extensionProperties.data());
    if (result != VK_SUCCESS) {
        return;
    }

    printf("Vulkan extension support:\n");
    for (auto& extension : extensionProperties) {
        printf("\t%s\n", extension.extensionName);
    }
}
void print_extensions_device()
{
    VkResult result;
    uint32_t count = 0;
    result = vkEnumerateDeviceExtensionProperties(physical_device,nullptr, &count, nullptr);
    if (result != VK_SUCCESS) {
        return;
    }
    std::vector<VkExtensionProperties> extensionProperties(count);

    result = vkEnumerateDeviceExtensionProperties(physical_device,nullptr, &count, extensionProperties.data());
    if (result != VK_SUCCESS) {
        return;
    }

    printf("Vulkan device extension support:\n");
    for (auto& extension : extensionProperties) {
        printf("\t%s\n", extension.extensionName);
    }
}
uint32_t find_queue_family()
{
    {
        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queueFamilyCount, nullptr);

        std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queueFamilyCount, queueFamilies.data());
        int i = 0;
        for (auto& f : queueFamilies)
        {
            
            VkBool32 presentSupport = false;
            vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, i, surface, &presentSupport);
            if ((f.queueFlags & VK_QUEUE_GRAPHICS_BIT) && (f.queueFlags & VK_QUEUE_COMPUTE_BIT) && presentSupport)
            {
                return i;
            }
            i++;
#if 0
            printf("Q: %d %d w:%d h:%d d:%d\n", f.queueCount,f.timestampValidBits,f.minImageTransferGranularity.width, f.minImageTransferGranularity.height, f.minImageTransferGranularity.depth);
#define X(v) if(!!(f.queueFlags&v))printf("\t" #v "\n");
            X(VK_QUEUE_GRAPHICS_BIT)
                X(VK_QUEUE_COMPUTE_BIT)
                X(VK_QUEUE_TRANSFER_BIT)
                X(VK_QUEUE_SPARSE_BINDING_BIT)
                X(VK_QUEUE_PROTECTED_BIT)
                X(VK_QUEUE_VIDEO_DECODE_BIT_KHR)
                //X(VK_QUEUE_VIDEO_ENCODE_BIT_KHR)
                X(VK_QUEUE_OPTICAL_FLOW_BIT_NV)
#undef X
#endif
        }
        return -1;
    }
}
int lua_open_vulkan(lua_State* L)
{
    return 0;
}
int init_vulkan(void* hwnd, void* hinstance)
{
    if (instance_inited)
        return -1;
    // Vulkan init
    const char* layers_requested[] = {
        "VK_LAYER_KHRONOS_validation"
    };
    VkResult result;
    //print_extensions();
    
    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    //todo option this?
    createInfo.enabledLayerCount = 1;
    createInfo.ppEnabledLayerNames = layers_requested;
    auto extensions = getRequiredExtensions();
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    result = vkCreateInstance(&createInfo, nullptr, &instance);
    if (result != VK_SUCCESS)
    {
        return -1;
    }
    //hookup debug messages
    {
        VkDebugUtilsMessengerCreateInfoEXT createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
        createInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
        createInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
        createInfo.pfnUserCallback = debugCallback;
        createInfo.pUserData = nullptr;
        if (CreateDebugUtilsMessengerEXT(instance, &createInfo, nullptr, &debugMessenger) != VK_SUCCESS) {
            throw std::runtime_error("failed to set up debug messenger!");
        }
    }
    //physical device selection
    {
        uint32_t dev_count = 0;
        vkEnumeratePhysicalDevices(instance, &dev_count, nullptr);
        std::vector<VkPhysicalDevice> devices(dev_count);
        vkEnumeratePhysicalDevices(instance, &dev_count, devices.data());
        for (auto& dev : devices)
        {
            VkPhysicalDeviceProperties deviceProperties;
            VkPhysicalDeviceFeatures deviceFeatures;
            vkGetPhysicalDeviceProperties(dev, &deviceProperties);
            vkGetPhysicalDeviceFeatures(dev, &deviceFeatures);

            if (deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU && deviceFeatures.geometryShader)
            {
                physical_device = dev;
                break;
            }
        }
        if (physical_device == VK_NULL_HANDLE)
        {
            throw std::runtime_error("failed to find gpu!");
        }
    }
    //print_extensions_device();
    {
        VkWin32SurfaceCreateInfoKHR createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
        createInfo.hinstance = (HINSTANCE)hinstance;
        createInfo.hwnd = (HWND)hwnd;
        if (vkCreateWin32SurfaceKHR(instance, &createInfo, nullptr, &surface) != VK_SUCCESS)
        {
            throw std::runtime_error("failed to create surface!");
        }
    }
    //logical device creation
    {
        auto queue_id = find_queue_family();

        VkDeviceQueueCreateInfo queueCreateInfo{};
        queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = queue_id;
        queueCreateInfo.queueCount = 1;
        float queuePriority = 1.0f;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        VkDeviceCreateInfo createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;

        VkPhysicalDeviceFeatures deviceFeatures{};
        createInfo.pEnabledFeatures = &deviceFeatures;

        createInfo.pQueueCreateInfos = &queueCreateInfo;
        createInfo.queueCreateInfoCount = 1;

        if (vkCreateDevice(physical_device, &createInfo, nullptr, &device) != VK_SUCCESS) {
            throw std::runtime_error("failed to create logical device!");
        }

        vkGetDeviceQueue(device, queue_id, 0, &basic_queue);
    }

    instance_inited = true;
    return 0;
}

static void cleanup()
{
    if (instance_inited)
    {
        vkDestroyDevice(device, nullptr);
        DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nullptr);
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        instance_inited = false;
    }
}