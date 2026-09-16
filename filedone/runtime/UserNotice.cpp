#include "UserNotice.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace filedone {
namespace {

bool TestMode() noexcept {
    wchar_t buffer[8]{};
    const DWORD capacity = static_cast<DWORD>(sizeof(buffer) / sizeof(buffer[0]));
    const DWORD n = GetEnvironmentVariableW(
        L"FILEDONE_TEST_MODE",
        buffer,
        capacity);
    return n == 1 && buffer[0] == L'1';
}

void Show(const wchar_t* message) noexcept {
    if (TestMode()) return;
    MessageBoxW(nullptr, message, L"FileDone", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}

} // namespace

void ShowOperationFailedNotice() noexcept {
    Show(L"FileDone couldn't finish this action.");
}

void ShowRuntimeUnavailableNotice() noexcept {
    Show(L"FileDone isn't ready right now. Please try again.");
}

void ShowInvalidRequestNotice() noexcept {
    Show(L"FileDone couldn't start this action.");
}

} // namespace filedone
