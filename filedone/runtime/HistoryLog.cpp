#include "HistoryLog.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <filesystem>
#include <string>
#include <vector>

namespace filedone {
namespace {

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) return {};
    const int needed = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS,
        value.data(), static_cast<int>(value.size()),
        nullptr, 0, nullptr, nullptr);
    if (needed <= 0) return {};

    std::string result(static_cast<size_t>(needed), '\0');
    const int written = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS,
        value.data(), static_cast<int>(value.size()),
        result.data(), needed, nullptr, nullptr);
    if (written != needed) return {};
    return result;
}

std::string JsonEscape(const std::string& value) {
    static const char hex[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(value.size() + 16);
    for (unsigned char ch : value) {
        switch (ch) {
        case '"': result += "\\\""; break;
        case '\\': result += "\\\\"; break;
        case '\b': result += "\\b"; break;
        case '\f': result += "\\f"; break;
        case '\n': result += "\\n"; break;
        case '\r': result += "\\r"; break;
        case '\t': result += "\\t"; break;
        default:
            if (ch < 0x20) {
                result += "\\u00";
                result += hex[(ch >> 4) & 0x0F];
                result += hex[ch & 0x0F];
            } else {
                result.push_back(static_cast<char>(ch));
            }
            break;
        }
    }
    return result;
}

std::wstring LocalAppData() {
    DWORD needed = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
    if (needed == 0) return {};
    std::vector<wchar_t> buffer(static_cast<size_t>(needed));
    const DWORD written = GetEnvironmentVariableW(
        L"LOCALAPPDATA", buffer.data(), static_cast<DWORD>(buffer.size()));
    if (written == 0 || written >= buffer.size()) return {};
    return std::wstring(buffer.data(), written);
}

std::string TimestampUtc() {
    SYSTEMTIME st{};
    GetSystemTime(&st);
    char buffer[40]{};
    const int written = _snprintf_s(
        buffer, sizeof(buffer), _TRUNCATE,
        "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        static_cast<unsigned int>(st.wYear),
        static_cast<unsigned int>(st.wMonth),
        static_cast<unsigned int>(st.wDay),
        static_cast<unsigned int>(st.wHour),
        static_cast<unsigned int>(st.wMinute),
        static_cast<unsigned int>(st.wSecond),
        static_cast<unsigned int>(st.wMilliseconds));
    if (written < 0) return {};
    return std::string(buffer, static_cast<size_t>(written));
}

std::string BuildLine(
    const std::string& action,
    const std::vector<std::wstring>& inputs,
    const std::wstring& output,
    const std::string& status,
    const std::string& detail) {

    std::string line = "{\"timestamp\":\"" + JsonEscape(TimestampUtc()) + "\",\"action\":\"" +
        JsonEscape(action) + "\",\"inputs\":[";
    for (size_t i = 0; i < inputs.size(); ++i) {
        if (i != 0) line += ',';
        line += "\"" + JsonEscape(WideToUtf8(inputs[i])) + "\"";
    }
    line += "],\"output\":\"" + JsonEscape(WideToUtf8(output)) +
        "\",\"status\":\"" + JsonEscape(status) +
        "\",\"detail\":\"" + JsonEscape(detail) + "\"}\r\n";
    return line;
}

} // namespace

void AppendHistoryLog(
    const std::string& action,
    const std::vector<std::wstring>& inputs,
    const std::wstring& output,
    const std::string& status,
    const std::string& detail) noexcept {

    HANDLE mutex = nullptr;
    HANDLE file = INVALID_HANDLE_VALUE;
    bool ownsMutex = false;
    try {
        const std::wstring base = LocalAppData();
        if (base.empty()) return;

        const auto directory = std::filesystem::path(base) / L"FileDone" / L"logs";
        std::error_code ec;
        std::filesystem::create_directories(directory, ec);
        if (ec) return;

        mutex = CreateMutexW(nullptr, FALSE, L"Local\\FileDone_Runtime_HistoryLog");
        if (mutex == nullptr) return;
        const DWORD wait = WaitForSingleObject(mutex, 5000);
        if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
            CloseHandle(mutex);
            return;
        }
        ownsMutex = true;

        const auto path = directory / L"runtime.jsonl";
        file = CreateFileW(
            path.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE) {
            ReleaseMutex(mutex);
            CloseHandle(mutex);
            return;
        }

        const std::string line = BuildLine(action, inputs, output, status, detail);
        DWORD written = 0;
        if (!line.empty()) {
            WriteFile(
                file,
                line.data(),
                static_cast<DWORD>(line.size()),
                &written,
                nullptr);
        }
    } catch (...) {
    }

    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    if (mutex != nullptr) {
        if (ownsMutex) ReleaseMutex(mutex);
        CloseHandle(mutex);
    }
}

} // namespace filedone
