#pragma once
#include <string>
#include <string_view>

namespace filedone {

enum class MediaKind {
    Image,
    Video,
    Audio,
    Unsupported
};

MediaKind ClassifyMedia(const std::wstring& path);
std::wstring CanonicalPath(const std::wstring& path);
std::wstring UniqueOutputPath(
    const std::wstring& input,
    std::wstring_view suffix,
    std::wstring_view extension);

} // namespace filedone
