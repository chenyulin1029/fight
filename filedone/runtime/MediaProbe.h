#pragma once
#include "Toolchain.h"
#include <string>

namespace filedone {

struct ImageSize {
    int width = 0;
    int height = 0;
};

struct VideoInfo {
    double duration = 0.0;
    std::string videoCodec;
    std::string audioCodec;
};

bool ImageIsOpaque(const Toolchain& tools, const std::wstring& path);
ImageSize GetImageSize(const Toolchain& tools, const std::wstring& path);
VideoInfo GetVideoInfo(const Toolchain& tools, const std::wstring& path);

} // namespace filedone
