#define WIN32_LITE_IMPLEMENTATION
#include "win32_lite.h"

int main(int argc, char** argv)
{
    //min_win::message_box("It works!", "Program", min_win::msg_type::info);
    min_win::window_state state = { 0 };
    state.w = 640;
    state.h = 480;
    min_win::show(state);
    min_win::event_loop(state);
}