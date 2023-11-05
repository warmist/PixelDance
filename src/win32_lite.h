//single header win32 "get me a screen" solution

//TODO: utf8ness

#ifndef WIN32_LITE_H_INCLUDED
#define WIN32_LITE_H_INCLUDED
#include <functional>
namespace min_win
{
    struct event
    {
    };

    typedef void* (* event_loop_t)(const event*,void*);
    typedef void* (__stdcall* win_callback_t)(void*, unsigned int, uint64_t*, uint64_t*);

    struct window_state
    {
        //settings
        int w;
        int h;
        //state
        void* hinstance;
        void* hwnd;
        event_loop_t event_callback;
        win_callback_t window_proc;
    };
    void show(window_state& state);
    void event_loop(window_state& state);
    //void event_tick(); //TODO: with timeout?

    enum class msg_type
    {
        warning,
        error,
        info,
    };
    void message_box(const char* message, const char* title, msg_type type);
};

#endif

//#include <Windows.h>

#ifdef WIN32_LITE_IMPLEMENTATION
extern "C" {
    //int __stdcall SetConsoleTitleW(const wchar_t* lpConsoleTitle);
    int __stdcall SetConsoleTitleA(const char* lpConsoleTitle);
    
    __declspec(dllimport) int
    __stdcall MessageBoxA(
        void* hWnd,
        const char* lpText,
        const char* lpCaption,
        unsigned int uType);

    __declspec(dllimport)
        void*
        __stdcall
        GetModuleHandleA(
            const char* lpModuleName
        );




    __declspec(dllimport)
        int
        __stdcall
        GetSystemMetrics(int nIndex);

    struct win_class_ex_A {
        unsigned int      cbSize;
        unsigned int      style;
        min_win::win_callback_t   lpfnWndProc;
        int       cbClsExtra;
        int       cbWndExtra;
        void* hInstance;
        void* hIcon;
        void* hCursor;
        void* hbrBackground;
        const char* lpszMenuName;
        const char* lpszClassName;
        void* hIconSm;
    };


    unsigned short __stdcall RegisterClassExA(
        const win_class_ex_A* lpwcx
    );

    __declspec(dllimport)
    void* __stdcall
        CreateWindowExA(
            unsigned long dwExStyle,
            const char* lpClassName,
            const char* lpWindowName,
            unsigned long dwStyle,
            int X,
            int Y,
            int nWidth,
            int nHeight,
            void* hWndParent,
            void* hMenu,
            void* hInstance,
            void* lpParam);

    __declspec(dllimport)
        int
        __stdcall
        DestroyWindow(
            void* hWnd);

    __declspec(dllimport)
        int
        __stdcall
        SetForegroundWindow(
            void* hWnd);

    __declspec(dllimport)
        int
        __stdcall
        ShowWindow(
            void* hWnd,
            int nCmdShow);

    __declspec(dllimport)
        void*
        __stdcall
        SetFocus(
            void* hWnd);

    __declspec(dllimport)
        void
        __stdcall
        PostQuitMessage(
            int nExitCode);

    __declspec(dllimport)
        int
        __stdcall
        ValidateRect(
            void* hWnd,
            void* lpRect);

    __declspec(dllimport)
        void*
        __stdcall
        DefWindowProcA(
            void* hWnd,
            unsigned int Msg,
            uint64_t* wParam,
            uint64_t* lParam);

    struct POINT
    {
        long  x;
        long  y;
    };

    struct MSG {
        void*        hwnd;
        unsigned int        message;
        uint64_t* wParam;
        uint64_t* lParam;
        unsigned long       time;
        POINT       pt;
    };

    __declspec(dllimport)
        int
        __stdcall
        GetMessageA(
            MSG* lpMsg,
            void* hWnd,
            unsigned int wMsgFilterMin,
            unsigned int wMsgFilterMax);

    __declspec(dllimport)
        int
        __stdcall
        TranslateMessage(
            const MSG* lpMsg);

    __declspec(dllimport)
        void*
        __stdcall
        DispatchMessageA(
            const MSG* lpMsg);
}
namespace min_win
{
    void* __stdcall win_proc(void* hwnd, unsigned int msg, uint64_t* wparam, uint64_t* lparam)
    {
        
#define WM_CREATE                       0x0001
#define WM_DESTROY                      0x0002
#define WM_MOVE                         0x0003
#define WM_SIZE                         0x0005
#define WM_PAINT                        0x000F

        switch (msg) {
        case WM_DESTROY:
            DestroyWindow(hwnd);
            PostQuitMessage(0);
            break;
        case WM_PAINT:
            ValidateRect(hwnd, NULL);
            break;
        default:
            return DefWindowProcA(hwnd, msg, wparam, lparam);
            break;
        }
        return nullptr;
    }
    void min_win::show(window_state& state)
    {
        if (state.hinstance == nullptr)
        {
            state.hinstance= GetModuleHandleA(NULL);
        }

        win_class_ex_A win_class={0};

        win_class.cbSize = sizeof(win_class);
        win_class.style = 0x1 | 0x2;
        if(state.window_proc)
            win_class.lpfnWndProc = state.window_proc;
        else
        win_class.lpfnWndProc = &win_proc;
        win_class.hInstance = state.hinstance;
        /*
        wcex.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_APPLICATION));
        wcex.hCursor = LoadCursor(NULL, IDC_ARROW);
        wcex.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
        wcex.lpszMenuName = NULL;
        wcex.hIconSm = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_APPLICATION));
        */
        win_class.lpszClassName = "win min win";
        
        int screen_w=GetSystemMetrics(0);//x
        int screen_h=GetSystemMetrics(1);//y

        int win_x = screen_w / 2 - state.w / 2;
        int win_y = screen_h / 2 - state.h / 2;

        auto win_atom=RegisterClassExA(&win_class);
        state.hwnd=CreateWindowExA(0,
            "win min win",
            "win min win",
            0x00C00000L |
            0x00080000L |
            0x00040000L |
            0x00020000L | //minimize
            0x00010000L | //maximize
            0x04000000L | 0x02000000L, win_x, win_y, state.w, state.h, nullptr, nullptr, state.hinstance, nullptr);

        ShowWindow(state.hwnd, 5);//SW_SHOW
        SetForegroundWindow(state.hwnd);
        SetFocus(state.hwnd);
    }
    void message_box(const char* message, const char* title, msg_type type)
    {
#if 0
#define MB_OK                       0x00000000L
#define MB_OKCANCEL                 0x00000001L
#define MB_ABORTRETRYIGNORE         0x00000002L
#define MB_YESNOCANCEL              0x00000003L
#define MB_YESNO                    0x00000004L
#define MB_RETRYCANCEL              0x00000005L
#define MB_CANCELTRYCONTINUE        0x00000006L

#define MB_ICONHAND                 0x00000010L
#define MB_ICONQUESTION             0x00000020L
#define MB_ICONEXCLAMATION          0x00000030L
#define MB_ICONASTERISK             0x00000040L

#define MB_USERICON                 0x00000080L
#define MB_ICONWARNING              MB_ICONEXCLAMATION
#define MB_ICONERROR                MB_ICONHAND
#define MB_ICONINFORMATION          MB_ICONASTERISK
#define MB_ICONSTOP                 MB_ICONHAND

#endif
        unsigned int icon = 0;
        switch (type)
        {
        case min_win::msg_type::warning:
            icon = 0x30L;
            break;
        case min_win::msg_type::error:
            icon = 0x10L;
            break;
        case min_win::msg_type::info:
            icon = 0x40L;
            break;
        default:
            break;
        }
        MessageBoxA(nullptr, message, title, icon);
    }
    void event_loop(window_state& state)
    {
        MSG message;

        while (GetMessageA(&message, NULL, 0, 0)) {
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
    }
}

#endif