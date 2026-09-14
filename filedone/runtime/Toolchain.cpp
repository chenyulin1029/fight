#include "Toolchain.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <filesystem>
#include <stdexcept>
#include <vector>

namespace filedone {
namespace {

std::filesystem::path RuntimeDirectory() {
    std::vector<wchar_t> buffer(32768);
    DWORD n = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (n == 0 || n >= buffer.size()) {
        throw std::runtime_error("GetModuleFileNameW failed");
    }
    return std::filesystem::path(std::wstring(buffer.data(), n)).parent_path();
}

std::filesystem::path ToolBaseDirectory() {
    wchar_t overrideBuffer[32768]{};
    DWORD n = GetEnvironmentVariableW(
        L"FILEDONE_TOOLS_DIR",
        overrideBuffer,
        static_cast<DWORD>(std::size(overrideBuffer)));
    if (n > 0 && n < std::size(overrideBuffer)) {
        return std::filesystem::path(std::wstring(overrideBuffer, n));
    }
    if (n >= std::size(overrideBuffer)) {
        throw std::runtime_error("FILEDONE_TOOLS_DIR is too long");
    }
    return RuntimeDirectory() / L"tools";
}

std::wstring RequireTool(const std::filesystem::path& path) {
    if (!std::filesystem::is_regular_file(path)) {
        throw std::runtime_error("required media tool missing");
    }
    return path.wstring();
}

} // namespace

Toolchain Toolchain::FromRuntimeDirectory() {
    const auto base = ToolBaseDirectory();
    Toolchain tools;
    tools.ffmpeg = RequireTool(base / L"ffmpeg.exe");
    tools.ffprobe = RequireTool(base / L"ffprobe.exe");
    tools.magick = RequireTool(base / L"magick.exe");
    return tools;
}

} // namespace filedone
