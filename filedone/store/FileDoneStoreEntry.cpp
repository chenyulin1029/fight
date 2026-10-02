#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    MessageBoxW(
        nullptr,
        L"FileDone works from Windows File Explorer.\n\nRight-click a file, then choose FileDone.",
        L"FileDone",
        MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
    return 0;
}
