#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include <app_links/app_links_plugin_c_api.h>
#include <string>

// Register only the current user's scheme; no machine-wide registry writes.
static void RegisterAmudProtocol() {
  wchar_t executable[MAX_PATH];
  if (!GetModuleFileNameW(nullptr, executable, MAX_PATH)) return;
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\amud", 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
  const wchar_t* label = L"URL:Amud prayer link";
  RegSetValueExW(key, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(label), static_cast<DWORD>((wcslen(label) + 1) * sizeof(wchar_t)));
  const wchar_t empty[] = L"";
  RegSetValueExW(key, L"URL Protocol", 0, REG_SZ, reinterpret_cast<const BYTE*>(empty), sizeof(empty));
  RegCloseKey(key);
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\amud\\shell\\open\\command", 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
  std::wstring command = L"\"" + std::wstring(executable) + L"\" \"%1\"";
  RegSetValueExW(key, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterAmudProtocol();
  if (HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Amud")) {
    SendAppLink(existing);
    ShowWindow(existing, SW_RESTORE);
    SetForegroundWindow(existing);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
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
  if (!window.Create(L"Amud", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
