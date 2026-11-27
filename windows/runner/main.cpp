#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"
// #include <protocol_handler_windows/protocol_handler_windows_plugin_c_api.h>

// NOTE: keep this file ASCII-only (the build uses /W4 /WX without /utf-8, a
// non-ASCII character in a source file is warning C4819 = build error).

// Window class of the Flutter runner window (win32_window.cpp, kWindowClassName).
static const wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Main window title. Since 0.1.105 it is "PIXELLNET"; up to and including 0.1.104
// it was "PIXELLNET VPN". A new copy finds the already running one by this title,
// so we look for BOTH: otherwise, when updating 0.1.104 -> 0.1.105, the new copy
// would not see the old one and would start next to it.
//
// IMPORTANT: the title "PIXELLNET" is the same as the folder name in Explorer
// (C:\Program Files\PIXELLNET), so never search by title alone - always together
// with the window class (an Explorer window has a different class).
static const wchar_t kWindowTitle[] = L"PIXELLNET";
static const wchar_t kLegacyWindowTitle[] = L"PIXELLNET VPN";

// Window of an already running copy of the app (new or legacy title), or nullptr.
static HWND FindInstanceWindow()
{
  HWND hwnd = ::FindWindow(kWindowClass, kWindowTitle);
  if (!hwnd)
  {
    hwnd = ::FindWindow(kWindowClass, kLegacyWindowTitle);
  }
  return hwnd;
}

bool SendAppLinkToInstance()
{
  // Find our exact window
  HWND hwnd = FindInstanceWindow();

  if (hwnd)
  {
    // Dispatch new link to current window
    SendAppLink(hwnd);

    // (Optional) Restore our window to front in same state
    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &place);

    switch (place.showCmd)
    {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
    }

    SetWindowPos(0, HWND_TOP, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hwnd);
    // END (Optional) Restore

    // Window has been found, don't create another one.
    return true;
  }

  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{

  // A copy is already running (including an older version whose window title is
  // "PIXELLNET VPN"): pass the link to it, bring its window to front and exit.
  if (SendAppLinkToInstance())
  {
    return EXIT_SUCCESS;
  }

  HANDLE hMutexInstance = CreateMutex(NULL, TRUE, L"PixellnetMutex");
  // Read the error code right away: a failed FindWindow overwrites it, and
  // "mutex already exists" would be lost - a second copy would start next to the first.
  const bool already_running = (GetLastError() == ERROR_ALREADY_EXISTS);
  HWND handle = FindInstanceWindow();

  if (already_running)
  {
    flutter::DartProject project(L"data");
    std::vector<std::string> command_line_arguments = GetCommandLineArguments();
    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
    FlutterWindow window(project);
    if (window.SendAppLinkToInstance(kWindowTitle) ||
        window.SendAppLinkToInstance(kLegacyWindowTitle))
    {
      return false;
    }

    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(handle, &place);
    ShowWindow(handle, SW_NORMAL);
    return 0;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(hMutexInstance);
  return EXIT_SUCCESS;
}
