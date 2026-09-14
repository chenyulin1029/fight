#pragma once
#include <string>

namespace filedone {

struct Toolchain {
    std::wstring ffmpeg;
    std::wstring ffprobe;
    std::wstring magick;

    static Toolchain FromRuntimeDirectory();
};

} // namespace filedone
