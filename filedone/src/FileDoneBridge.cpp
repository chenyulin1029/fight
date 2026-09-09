#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>

static std::wstring LocalAppData()
{
    wchar_t buf[32768]{};
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, ARRAYSIZE(buf));
    return (n && n < ARRAYSIZE(buf)) ? std::wstring(buf, n) : L"";
}

static std::wstring Quote(const std::wstring& s)
{
    return L"\"" + s + L"\"";
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv || argc < 2)
    {
        if (argv) LocalFree(argv);
        return 2;
    }

    std::wstring request = argv[1];
    LocalFree(argv);

    std::wstring base = LocalAppData();
    if (base.empty()) return 3;

    std::wstring dispatcher = base + L"\\FileDone\\FileDoneShellDispatch.ps1";
    if (GetFileAttributesW(dispatcher.c_str()) == INVALID_FILE_ATTRIBUTES)
        return 4;

    std::wstring cmd =
        L"powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " +
        Quote(dispatcher) + L" -RequestFile " + Quote(request);

    std::vector<wchar_t> mutableCmd(cmd.begin(), cmd.end());
    mutableCmd.push_back(L'\0');

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};

    BOOL ok = CreateProcessW(
        nullptr, mutableCmd.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
        nullptr, nullptr, &si, &pi);

    if (!ok) return (int)GetLastError();

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
