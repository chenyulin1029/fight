#include "MediaProbe.h"
#include "ProcessRunner.h"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <stdexcept>

namespace filedone {
namespace {

std::string TrimAscii(std::string value) {
    auto notSpace = [](unsigned char ch) { return !std::isspace(ch); };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), notSpace));
    value.erase(std::find_if(value.rbegin(), value.rend(), notSpace).base(), value.end());
    return value;
}

std::string LowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        if (ch >= 'A' && ch <= 'Z') return static_cast<char>(ch - 'A' + 'a');
        return static_cast<char>(ch);
    });
    return value;
}

std::string RequireSuccessText(
    const std::wstring& exe,
    const std::vector<std::wstring>& args) {

    auto result = RunProcess(exe, args);
    if (result.exitCode != 0) {
        throw std::runtime_error("media probe failed");
    }
    return TrimAscii(result.stdoutText);
}

} // namespace

bool ImageIsOpaque(const Toolchain& tools, const std::wstring& path) {
    auto text = RequireSuccessText(
        tools.magick,
        {L"identify", L"-quiet", L"-format", L"%[opaque]", path});
    text = LowerAscii(text);
    if (text == "true") return true;
    if (text == "false") return false;
    throw std::runtime_error("unexpected ImageMagick opacity result");
}

ImageSize GetImageSize(const Toolchain& tools, const std::wstring& path) {
    const auto text = RequireSuccessText(
        tools.magick,
        {L"identify", L"-quiet", L"-format", L"%w %h", path});

    std::istringstream in(text);
    ImageSize size;
    in >> size.width >> size.height;
    if (!in || size.width <= 0 || size.height <= 0) {
        throw std::runtime_error("unexpected ImageMagick dimension result");
    }
    return size;
}

VideoInfo GetVideoInfo(const Toolchain& tools, const std::wstring& path) {
    VideoInfo info;

    const auto durationText = RequireSuccessText(
        tools.ffprobe,
        {L"-v", L"error", L"-show_entries", L"format=duration",
         L"-of", L"default=noprint_wrappers=1:nokey=1", path});
    try {
        info.duration = std::stod(durationText);
    } catch (...) {
        throw std::runtime_error("unexpected FFprobe duration result");
    }

    info.videoCodec = RequireSuccessText(
        tools.ffprobe,
        {L"-v", L"error", L"-select_streams", L"v:0",
         L"-show_entries", L"stream=codec_name",
         L"-of", L"default=noprint_wrappers=1:nokey=1", path});

    auto audio = RunProcess(
        tools.ffprobe,
        {L"-v", L"error", L"-select_streams", L"a:0",
         L"-show_entries", L"stream=codec_name",
         L"-of", L"default=noprint_wrappers=1:nokey=1", path});
    if (audio.exitCode != 0) {
        throw std::runtime_error("FFprobe audio probe failed");
    }
    info.audioCodec = TrimAscii(audio.stdoutText);
    return info;
}

} // namespace filedone
