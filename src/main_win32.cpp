#define WIN32_LITE_IMPLEMENTATION
#include "win32_lite.h"
#include "imgui.h"

#include "backends/imgui_impl_win32.h"
#include "backends/imgui_impl_vulkan.h"

#include "lua_vk.h"

int main(int argc, char** argv)
{
    //min_win::message_box("It works!", "Program", min_win::msg_type::info);
    min_win::window_state state = { 0 };
    state.w = 640;
    state.h = 480;
    min_win::show(state);

    init_vulkan(state.hwnd, state.hinstance);
    IMGUI_CHECKVERSION();
    auto im_context=ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;   // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;    // Enable Gamepad Controls

    // Setup Dear ImGui style
    ImGui::StyleColorsDark();
    //ImGui::StyleColorsClassic();

    min_win::event_loop(state);
}