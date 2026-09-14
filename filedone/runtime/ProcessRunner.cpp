#include "ProcessRunner.h"

#include <stdexcept>
#include <thread>
#include <utility>

namespace filedone {
namespace {

std::wstring QuoteWindowsArgument(const std::wstring& arg) {
    if (arg.empty()) return L"\"\"";

    bool needsQuotes = false;
    for (wchar_t ch : arg) {
        if (ch == L' ' || ch == L'\t' || ch == L'\n' || ch == L'\v' || ch == L'\"') {
            needsQuotes = true;
            break;
        }
    }
    if (!needsQuotes) return arg;

    std::wstring out;
    out.push_back(L'\"');
    size_t slashCount = 0;
    for (wchar_t ch : arg) {
        if (ch == L'\\') {
            ++slashCount;
            continue;
        }

        if (ch == L'\"') {
            out.append(slashCount * 2 + 1, L'\\');
            out.push_back(L'\"');
        } else {
            out.append(slashCount, L'\\');
            out.push_back(ch);
        }
        slashCount = 0;
    }

    out.append(slashCount * 2, L'\\');
    out.push_back(L'\"');
    return out;
}

void CloseIfValid(HANDLE& handle) noexcept {
    if (handle && handle != INVALID_HANDLE_VALUE) {
        CloseHandle(handle);
        handle = nullptr;
    }
}

std::string ReadPipeFully(HANDLE pipe) {
    std::string output;
    char buffer[4096];
    for (;;) {
        DWORD read = 0;
        BOOL ok = ReadFile(pipe, buffer, static_cast<DWORD>(sizeof(buffer)), &read, nullptr);
        if (ok && read > 0) {
            output.append(buffer, buffer + read);
            continue;
        }
        if (!ok && GetLastError() == ERROR_BROKEN_PIPE) break;
        if (ok && read == 0) break;
        throw std::runtime_error("ReadFile pipe failed");
    }
    return output;
}

} // namespace

std::wstring BuildWindowsCommandLine(
    const std::wstring& exe,
    const std::vector<std::wstring>& args) {

    std::wstring commandLine = QuoteWindowsArgument(exe);
    for (const auto& arg : args) {
        commandLine.push_back(L' ');
        commandLine += QuoteWindowsArgument(arg);
    }
    return commandLine;
}

ProcessResult RunProcess(
    const std::wstring& exe,
    const std::vector<std::wstring>& args) {

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE stdoutRead = nullptr;
    HANDLE stdoutWrite = nullptr;
    HANDLE stderrRead = nullptr;
    HANDLE stderrWrite = nullptr;

    if (!CreatePipe(&stdoutRead, &stdoutWrite, &sa, 0)) {
        throw std::runtime_error("CreatePipe stdout failed");
    }
    if (!SetHandleInformation(stdoutRead, HANDLE_FLAG_INHERIT, 0)) {
        CloseIfValid(stdoutRead);
        CloseIfValid(stdoutWrite);
        throw std::runtime_error("SetHandleInformation stdout failed");
    }
    if (!CreatePipe(&stderrRead, &stderrWrite, &sa, 0)) {
        CloseIfValid(stdoutRead);
        CloseIfValid(stdoutWrite);
        throw std::runtime_error("CreatePipe stderr failed");
    }
    if (!SetHandleInformation(stderrRead, HANDLE_FLAG_INHERIT, 0)) {
        CloseIfValid(stdoutRead);
        CloseIfValid(stdoutWrite);
        CloseIfValid(stderrRead);
        CloseIfValid(stderrWrite);
        throw std::runtime_error("SetHandleInformation stderr failed");
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = stdoutWrite;
    si.hStdError = stderrWrite;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION pi{};
    std::wstring commandLine = BuildWindowsCommandLine(exe, args);
    std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
    mutableCommand.push_back(L'\0');

    BOOL created = CreateProcessW(
        exe.c_str(),
        mutableCommand.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
        nullptr,
        nullptr,
        &si,
        &pi);

    CloseIfValid(stdoutWrite);
    CloseIfValid(stderrWrite);

    if (!created) {
        CloseIfValid(stdoutRead);
        CloseIfValid(stderrRead);
        throw std::runtime_error("CreateProcessW failed");
    }

    std::string stdoutText;
    std::string stderrText;
    std::exception_ptr stdoutError;
    std::exception_ptr stderrError;

    std::thread stdoutThread([&] {
        try { stdoutText = ReadPipeFully(stdoutRead); }
        catch (...) { stdoutError = std::current_exception(); }
    });
    std::thread stderrThread([&] {
        try { stderrText = ReadPipeFully(stderrRead); }
        catch (...) { stderrError = std::current_exception(); }
    });

    DWORD wait = WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exitCode = 0;
    if (wait != WAIT_OBJECT_0 || !GetExitCodeProcess(pi.hProcess, &exitCode)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        stdoutThread.join();
        stderrThread.join();
        CloseIfValid(stdoutRead);
        CloseIfValid(stderrRead);
        throw std::runtime_error("child process wait failed");
    }

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    stdoutThread.join();
    stderrThread.join();
    CloseIfValid(stdoutRead);
    CloseIfValid(stderrRead);

    if (stdoutError) std::rethrow_exception(stdoutError);
    if (stderrError) std::rethrow_exception(stderrError);

    return ProcessResult{exitCode, std::move(stdoutText), std::move(stderrText)};
}

} // namespace filedone
