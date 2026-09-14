#include "PathPolicy.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace filedone {
namespace {

std::wstring LowerAscii(std::wstring s) {
    for (auto& ch : s) {
        if (ch >= L'A' && ch <= L'Z') ch = static_cast<wchar_t>(ch - L'A' + L'a');
    }
    return s;
}

bool IsOneOf(const std::wstring& value, const wchar_t* const* values, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if (value == values[i]) return true;
    }
    return false;
}

} // namespace

MediaKind ClassifyMedia(const std::wstring& path) {
    static const wchar_t* imageExts[] = {
        L".jpg", L".jpeg", L".png", L".gif", L".webp", L".avif",
        L".heic", L".heif", L".tif", L".tiff", L".bmp"
    };
    static const wchar_t* videoExts[] = {
        L".mp4", L".mov", L".mkv", L".webm", L".avi", L".wmv", L".m4v"
    };
    static const wchar_t* audioExts[] = {
        L".mp3", L".flac", L".wav", L".ogg", L".opus", L".m4a", L".aac", L".wma"
    };

    auto ext = LowerAscii(std::filesystem::path(path).extension().wstring());
    if (IsOneOf(ext, imageExts, _countof(imageExts))) return MediaKind::Image;
    if (IsOneOf(ext, videoExts, _countof(videoExts))) return MediaKind::Video;
    if (IsOneOf(ext, audioExts, _countof(audioExts))) return MediaKind::Audio;
    return MediaKind::Unsupported;
}

std::wstring CanonicalPath(const std::wstring& path) {
    DWORD needed = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (needed == 0) throw std::runtime_error("GetFullPathNameW size failed");

    std::wstring result(needed, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), needed, result.data(), nullptr);
    if (written == 0 || written >= needed) {
        throw std::runtime_error("GetFullPathNameW failed");
    }
    result.resize(written);
    return result;
}

std::wstring UniqueOutputPath(
    const std::wstring& input,
    std::wstring_view suffix,
    std::wstring_view extension) {

    std::filesystem::path source(input);
    auto dir = source.parent_path();
    auto stem = source.stem().wstring();

    std::wstring ext(extension);
    if (ext.empty() || ext.front() != L'.') ext.insert(ext.begin(), L'.');

    std::filesystem::path candidate = dir / (stem + std::wstring(suffix) + ext);
    unsigned int index = 2;
    while (std::filesystem::exists(candidate)) {
        candidate = dir / (
            stem + std::wstring(suffix) + L"_" + std::to_wstring(index) + ext);
        ++index;
    }
    return candidate.wstring();
}

} // namespace filedone
