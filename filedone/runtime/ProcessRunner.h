#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>

namespace filedone {

struct ProcessResult {
    DWORD exitCode = 0;
    std::string stdoutText;
    std::string stderrText;
};

std::wstring BuildWindowsCommandLine(
    const std::wstring& exe,
    const std::vector<std::wstring>& args);

ProcessResult RunProcess(
    const std::wstring& exe,
    const std::vector<std::wstring>& args);

} // namespace filedone
