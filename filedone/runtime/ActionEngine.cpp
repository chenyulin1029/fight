#include "ActionEngine.h"
#include "MediaProbe.h"
#include "PathPolicy.h"
#include "ProcessRunner.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

namespace filedone {
namespace {

std::wstring LowerAscii(std::wstring value) {
    for (auto& ch : value) {
        if (ch >= L'A' && ch <= L'Z') ch = static_cast<wchar_t>(ch - L'A' + L'a');
    }
    return value;
}

std::wstring ExtensionLower(const std::wstring& path) {
    return LowerAscii(std::filesystem::path(path).extension().wstring());
}

bool IsExtension(const std::wstring& ext, std::initializer_list<const wchar_t*> values) {
    for (const auto* value : values) {
        if (ext == value) return true;
    }
    return false;
}

void RemoveQuietly(const std::wstring& path) noexcept {
    if (path.empty()) return;
    std::error_code ec;
    std::filesystem::remove(std::filesystem::path(path), ec);
}

std::uintmax_t FileSize(const std::wstring& path) {
    std::error_code ec;
    const auto size = std::filesystem::file_size(std::filesystem::path(path), ec);
    if (ec) throw std::runtime_error("cannot read output file size");
    return size;
}

std::uintmax_t TargetBytes(double targetMb) {
    if (!std::isfinite(targetMb) || targetMb <= 0.0) {
        throw std::runtime_error("target size must be greater than zero");
    }
    const long double bytes = static_cast<long double>(targetMb) * 1024.0L * 1024.0L;
    if (bytes < 1.0L ||
        bytes > static_cast<long double>((std::numeric_limits<std::uintmax_t>::max)())) {
        throw std::runtime_error("target size is out of range");
    }
    return static_cast<std::uintmax_t>(std::floor(bytes));
}

std::wstring FitUnderSuffix(double targetMb) {
    std::wostringstream stream;
    stream.imbue(std::locale::classic());
    stream << std::setprecision(15) << std::defaultfloat << targetMb;
    return L"_under_" + stream.str() + L"MB";
}

void RequireOutput(const std::wstring& path) {
    std::error_code ec;
    const auto p = std::filesystem::path(path);
    if (!std::filesystem::is_regular_file(p, ec) || ec) {
        RemoveQuietly(path);
        throw std::runtime_error("expected output file missing");
    }
    const auto size = std::filesystem::file_size(p, ec);
    if (ec || size == 0) {
        RemoveQuietly(path);
        throw std::runtime_error("expected output file empty");
    }
}

void RunRequired(const std::wstring& exe, const std::vector<std::wstring>& args) {
    const auto result = RunProcess(exe, args);
    if (result.exitCode != 0) {
        throw std::runtime_error(
            result.stderrText.empty() ? "media tool failed" : result.stderrText);
    }
}

void RunProducing(
    const std::wstring& exe,
    const std::vector<std::wstring>& args,
    const std::wstring& output) {

    const auto result = RunProcess(exe, args);
    if (result.exitCode != 0) {
        RemoveQuietly(output);
        throw std::runtime_error(
            result.stderrText.empty() ? "media conversion failed" : result.stderrText);
    }
    RequireOutput(output);
}

struct EncoderCapabilities {
    bool h264Legacy = false;
    bool mp3Legacy = false;
    bool h264MediaFoundation = false;
    bool mp3MediaFoundation = false;
};

bool EncoderListContains(const std::string& text, const std::string& wanted) {
    std::istringstream input(text);
    std::string line;
    while (std::getline(input, line)) {
        std::istringstream row(line);
        std::string flags;
        std::string name;
        if ((row >> flags >> name) && name == wanted) return true;
    }
    return false;
}

EncoderCapabilities DetectEncoderCapabilities(const Toolchain& tools) {
    const auto result = RunProcess(tools.ffmpeg, {L"-hide_banner", L"-encoders"});
    if (result.exitCode != 0) {
        throw std::runtime_error(
            result.stderrText.empty() ? "FFmpeg encoder probe failed" : result.stderrText);
    }

    const std::string text = result.stdoutText + "\n" + result.stderrText;
    EncoderCapabilities capabilities;
    capabilities.h264Legacy = EncoderListContains(text, "libx264");
    capabilities.mp3Legacy = EncoderListContains(text, "libmp3lame");
    capabilities.h264MediaFoundation = EncoderListContains(text, "h264_mf");
    capabilities.mp3MediaFoundation = EncoderListContains(text, "mp3_mf");
    return capabilities;
}

size_t ImageFrameCount(const Toolchain& tools, const std::wstring& path) {
    const auto result = RunProcess(tools.magick, {L"identify", L"-quiet", path});
    if (result.exitCode != 0) {
        throw std::runtime_error("ImageMagick frame probe failed");
    }
    size_t count = 0;
    bool inLine = false;
    for (char ch : result.stdoutText) {
        if (ch == '\r' || ch == '\n') {
            if (inLine) {
                ++count;
                inLine = false;
            }
        } else {
            inLine = true;
        }
    }
    if (inLine) ++count;
    return count;
}

void CleanupPassLogs(const std::filesystem::path& prefix) noexcept {
    std::error_code ec;
    const auto parent = prefix.parent_path();
    const auto wantedPrefix = prefix.filename().wstring();
    if (!std::filesystem::is_directory(parent, ec) || ec) return;

    std::filesystem::directory_iterator it(parent, ec);
    std::filesystem::directory_iterator end;
    while (!ec && it != end) {
        const auto name = it->path().filename().wstring();
        if (name.size() >= wantedPrefix.size() &&
            name.compare(0, wantedPrefix.size(), wantedPrefix) == 0) {
            std::error_code removeEc;
            std::filesystem::remove(it->path(), removeEc);
        }
        it.increment(ec);
    }
}

ActionResult Pass(std::wstring output, std::string note = {}) {
    return ActionResult{ActionOutcome::Pass, std::move(output), std::move(note)};
}

ActionResult Noop(std::string note) {
    return ActionResult{ActionOutcome::Noop, L"", std::move(note)};
}

ActionResult FitImageUnder(
    const Toolchain& tools,
    const std::wstring& path,
    std::uintmax_t targetBytes,
    const std::wstring& outputSuffix) {

    static constexpr double kScales[] = {1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4};
    static constexpr int kQualities[] = {88, 82, 76, 70, 64, 58, 52, 46, 40};

    const bool opaque = ImageIsOpaque(tools, path);
    const auto dimensions = GetImageSize(tools, path);
    if (dimensions.width <= 0 || dimensions.height <= 0) {
        throw std::runtime_error("invalid image dimensions");
    }

    const auto output = UniqueOutputPath(
        path,
        outputSuffix,
        opaque ? L".jpg" : L".webp");

    try {
        for (double scale : kScales) {
            const auto scaledWidth = static_cast<int>(std::lround(static_cast<double>(dimensions.width) * scale));
            const auto scaledHeight = static_cast<int>(std::lround(static_cast<double>(dimensions.height) * scale));
            if (scale < 1.0 && (scaledWidth < 320 || scaledHeight < 320)) {
                continue;
            }

            const int percent = static_cast<int>(std::lround(scale * 100.0));
            const std::wstring resize = std::to_wstring(percent) + L"%";
            for (int quality : kQualities) {
                RemoveQuietly(output);
                RunProducing(
                    tools.magick,
                    {path,
                     L"-auto-orient",
                     L"-strip",
                     L"-resize", resize,
                     L"-quality", std::to_wstring(quality),
                     output},
                    output);

                if (FileSize(output) <= targetBytes) {
                    return Pass(output);
                }
            }
        }
    } catch (...) {
        RemoveQuietly(output);
        throw;
    }

    RemoveQuietly(output);
    throw std::runtime_error("image cannot fit under requested size without crossing minimum dimensions");
}

ActionResult FitVideoUnder(
    const Toolchain& tools,
    const std::wstring& path,
    std::uintmax_t targetBytes,
    const std::wstring& outputSuffix) {

    const auto info = GetVideoInfo(tools, path);
    if (!std::isfinite(info.duration) || info.duration <= 0.0) {
        throw std::runtime_error("video duration unavailable");
    }

    constexpr std::int64_t kAudioBps = 96000;
    constexpr std::int64_t kMinimumVideoBps = 140000;

    const double totalBps =
        static_cast<double>(targetBytes) * 8.0 * 0.965 / info.duration;
    if (!std::isfinite(totalBps)) {
        throw std::runtime_error("target bitrate is out of range");
    }

    std::int64_t videoBps = static_cast<std::int64_t>(std::floor(totalBps - static_cast<double>(kAudioBps)));
    if (videoBps < kMinimumVideoBps) {
        throw std::runtime_error("target size is too small for the minimum video bitrate");
    }

    const auto output = UniqueOutputPath(path, outputSuffix, L".mp4");
    const auto passPrefix = std::filesystem::path(output + L".passlog");
    const std::wstring filter = L"scale=1920:-2:force_original_aspect_ratio=decrease";
    int attempt = 0;

    try {
        while (videoBps >= kMinimumVideoBps) {
            ++attempt;
            RemoveQuietly(output);
            CleanupPassLogs(passPrefix);
            const std::wstring bitrate = std::to_wstring(videoBps);

            const auto encoders = DetectEncoderCapabilities(tools);
            if (!encoders.h264Legacy && encoders.h264MediaFoundation) {
                const std::wstring mfFilter = filter + L",format=nv12";
                RunProducing(
                    tools.ffmpeg,
                    {L"-hide_banner", L"-loglevel", L"error", L"-y",
                     L"-i", path,
                     L"-map", L"0:v:0", L"-map", L"0:a?",
                     L"-vf", mfFilter,
                     L"-c:v", L"h264_mf",
                     L"-hw_encoding", L"0",
                     L"-rate_control", L"cbr",
                     L"-b:v", bitrate,
                     L"-pix_fmt", L"nv12",
                     L"-c:a", L"aac", L"-b:a", L"96k",
                     L"-movflags", L"+faststart",
                     output},
                    output);
            } else {
                RunRequired(
                    tools.ffmpeg,
                    {L"-hide_banner", L"-loglevel", L"error", L"-y",
                     L"-i", path,
                     L"-map", L"0:v:0",
                     L"-vf", filter,
                     L"-c:v", L"libx264", L"-preset", L"medium", L"-b:v", bitrate,
                     L"-pix_fmt", L"yuv420p",
                     L"-pass", L"1", L"-passlogfile", passPrefix.wstring(),
                     L"-an", L"-f", L"mp4", L"NUL"});

                RunProducing(
                    tools.ffmpeg,
                    {L"-hide_banner", L"-loglevel", L"error", L"-y",
                     L"-i", path,
                     L"-map", L"0:v:0", L"-map", L"0:a?",
                     L"-vf", filter,
                     L"-c:v", L"libx264", L"-preset", L"medium", L"-b:v", bitrate,
                     L"-pix_fmt", L"yuv420p",
                     L"-pass", L"2", L"-passlogfile", passPrefix.wstring(),
                     L"-c:a", L"aac", L"-b:a", L"96k",
                     L"-movflags", L"+faststart",
                     output},
                    output);
            }

            CleanupPassLogs(passPrefix);
            if (FileSize(output) <= targetBytes) {
                return Pass(
                    output,
                    attempt > 2
                        ? "strict-target continuation below legacy 1.01 tolerance"
                        : (attempt == 2 ? "strict-target 90-percent retry" : std::string{}));
            }

            RemoveQuietly(output);
            const auto next = static_cast<std::int64_t>(std::floor(static_cast<double>(videoBps) * 0.90));
            if (next >= videoBps) break;
            videoBps = next;
        }
    } catch (...) {
        CleanupPassLogs(passPrefix);
        RemoveQuietly(output);
        throw;
    }

    CleanupPassLogs(passPrefix);
    RemoveQuietly(output);
    throw std::runtime_error("video cannot fit under requested size at the minimum bitrate");
}

} // namespace

ActionResult ExecuteCompatible(const Toolchain& tools, const std::wstring& path) {
    const auto ext = ExtensionLower(path);

    if (IsExtension(ext, {L".jpg", L".jpeg", L".png", L".gif", L".mp3"})) {
        return Noop("already compatible");
    }

    const auto kind = ClassifyMedia(path);
    if (kind == MediaKind::Image) {
        if (ext == L".webp" && ImageFrameCount(tools, path) > 1) {
            throw std::runtime_error("animated WebP is not supported by Make Compatible");
        }

        const bool opaque = ImageIsOpaque(tools, path);
        if (opaque) {
            const auto output = UniqueOutputPath(path, L"_compatible", L".jpg");
            RunProducing(
                tools.magick,
                {path, L"-auto-orient", L"-quality", L"90", output},
                output);
            return Pass(output);
        }

        const auto output = UniqueOutputPath(path, L"_compatible", L".png");
        RunProducing(tools.magick, {path, L"-auto-orient", output}, output);
        return Pass(output);
    }

    if (kind == MediaKind::Video) {
        const auto info = GetVideoInfo(tools, path);
        if (ext == L".mp4" && info.videoCodec == "h264" &&
            (info.audioCodec == "aac" || info.audioCodec.empty())) {
            return Noop("already H.264/AAC MP4");
        }

        const auto output = UniqueOutputPath(path, L"_compatible", L".mp4");
        const auto encoders = DetectEncoderCapabilities(tools);
        if (!encoders.h264Legacy && encoders.h264MediaFoundation) {
            RunProducing(
                tools.ffmpeg,
                {L"-hide_banner", L"-loglevel", L"error", L"-y",
                 L"-i", path,
                 L"-map", L"0:v:0", L"-map", L"0:a?",
                 L"-vf", L"format=nv12",
                 L"-c:v", L"h264_mf",
                 L"-hw_encoding", L"0",
                 L"-rate_control", L"cbr",
                 L"-b:v", L"5000k",
                 L"-pix_fmt", L"nv12",
                 L"-c:a", L"aac", L"-b:a", L"160k",
                 L"-movflags", L"+faststart", output},
                output);
        } else {
            RunProducing(
                tools.ffmpeg,
                {L"-hide_banner", L"-loglevel", L"error", L"-y",
                 L"-i", path,
                 L"-map", L"0:v:0", L"-map", L"0:a?",
                 L"-c:v", L"libx264", L"-preset", L"medium", L"-crf", L"20",
                 L"-pix_fmt", L"yuv420p",
                 L"-c:a", L"aac", L"-b:a", L"160k",
                 L"-movflags", L"+faststart", output},
                output);
        }
        return Pass(output);
    }

    if (kind == MediaKind::Audio) {
        const auto output = UniqueOutputPath(path, L"_compatible", L".mp3");
        const auto encoders = DetectEncoderCapabilities(tools);
        RunProducing(
            tools.ffmpeg,
            {L"-hide_banner", L"-loglevel", L"error", L"-y",
             L"-i", path, L"-vn", L"-c:a",
             (!encoders.mp3Legacy && encoders.mp3MediaFoundation) ? L"mp3_mf" : L"libmp3lame",
             L"-b:a", L"192k", output},
            output);
        return Pass(output);
    }

    throw std::runtime_error("unsupported file type for Make Compatible");
}

ActionResult ExecuteSmaller(const Toolchain& tools, const std::wstring& path) {
    const auto kind = ClassifyMedia(path);

    if (kind == MediaKind::Image) {
        const bool opaque = ImageIsOpaque(tools, path);
        if (opaque) {
            const auto output = UniqueOutputPath(path, L"_smaller", L".jpg");
            RunProducing(
                tools.magick,
                {path, L"-auto-orient", L"-strip", L"-resize", L"2560x2560>",
                 L"-quality", L"82", output},
                output);
            return Pass(output);
        }

        const auto output = UniqueOutputPath(path, L"_smaller", L".webp");
        RunProducing(
            tools.magick,
            {path, L"-auto-orient", L"-strip", L"-resize", L"2560x2560>",
             L"-quality", L"82", output},
            output);
        return Pass(output);
    }

    if (kind == MediaKind::Video) {
        const auto output = UniqueOutputPath(path, L"_smaller", L".mp4");
        const auto encoders = DetectEncoderCapabilities(tools);
        if (!encoders.h264Legacy && encoders.h264MediaFoundation) {
            RunProducing(
                tools.ffmpeg,
                {L"-hide_banner", L"-loglevel", L"error", L"-y",
                 L"-i", path,
                 L"-map", L"0:v:0", L"-map", L"0:a?",
                 L"-vf", L"scale=1920:-2:force_original_aspect_ratio=decrease,format=nv12",
                 L"-c:v", L"h264_mf",
                 L"-hw_encoding", L"0",
                 L"-rate_control", L"cbr",
                 L"-b:v", L"2500k",
                 L"-pix_fmt", L"nv12",
                 L"-c:a", L"aac", L"-b:a", L"128k",
                 L"-movflags", L"+faststart", output},
                output);
        } else {
            RunProducing(
                tools.ffmpeg,
                {L"-hide_banner", L"-loglevel", L"error", L"-y",
                 L"-i", path,
                 L"-map", L"0:v:0", L"-map", L"0:a?",
                 L"-vf", L"scale=1920:-2:force_original_aspect_ratio=decrease",
                 L"-c:v", L"libx264", L"-preset", L"medium", L"-crf", L"28",
                 L"-pix_fmt", L"yuv420p",
                 L"-c:a", L"aac", L"-b:a", L"128k",
                 L"-movflags", L"+faststart", output},
                output);
        }
        return Pass(output);
    }

    if (kind == MediaKind::Audio) {
        const auto output = UniqueOutputPath(path, L"_smaller", L".mp3");
        const auto encoders = DetectEncoderCapabilities(tools);
        RunProducing(
            tools.ffmpeg,
            {L"-hide_banner", L"-loglevel", L"error", L"-y",
             L"-i", path, L"-vn", L"-c:a",
             (!encoders.mp3Legacy && encoders.mp3MediaFoundation) ? L"mp3_mf" : L"libmp3lame",
             L"-b:a", L"128k", output},
            output);
        return Pass(output);
    }

    throw std::runtime_error("unsupported file type for Make Smaller");
}

ActionResult ExecuteSafeShare(const Toolchain& tools, const std::wstring& path) {
    const auto kind = ClassifyMedia(path);
    const auto ext = ExtensionLower(path);

    if (kind == MediaKind::Image) {
        if (ext == L".heic" || ext == L".heif") {
            const auto output = UniqueOutputPath(path, L"_safe", L".jpg");
            RunProducing(
                tools.magick,
                {path, L"-auto-orient", L"-strip", L"-quality", L"92", output},
                output);
            return Pass(output);
        }

        const auto output = UniqueOutputPath(path, L"_safe", ext);
        RunProducing(
            tools.magick,
            {path, L"-auto-orient", L"-strip", output},
            output);
        return Pass(output);
    }

    if (kind == MediaKind::Video || kind == MediaKind::Audio) {
        const auto output = UniqueOutputPath(path, L"_safe", ext);
        RunProducing(
            tools.ffmpeg,
            {L"-hide_banner", L"-loglevel", L"error", L"-y",
             L"-i", path,
             L"-map", L"0",
             L"-map_metadata", L"-1",
             L"-map_chapters", L"-1",
             L"-c", L"copy",
             output},
            output);
        return Pass(output);
    }

    throw std::runtime_error("unsupported file type for Safe to Share");
}

ActionResult ExecuteMakePdf(const Toolchain& tools, const std::vector<std::wstring>& paths) {
    if (paths.empty()) {
        throw std::runtime_error("Make PDF requires at least one image");
    }

    for (const auto& path : paths) {
        if (ClassifyMedia(path) != MediaKind::Image) {
            throw std::runtime_error("Make PDF accepts images only");
        }
    }

    const auto output = UniqueOutputPath(paths.front(), L"_document", L".pdf");
    std::vector<std::wstring> args;
    args.reserve(paths.size() + 7);
    args.insert(args.end(), paths.begin(), paths.end());
    args.push_back(L"-auto-orient");
    args.push_back(L"-units");
    args.push_back(L"PixelsPerInch");
    args.push_back(L"-density");
    args.push_back(L"150");
    args.push_back(output);

    RunProducing(tools.magick, args, output);
    return Pass(output);
}

ActionResult ExecuteFitUnder(const Toolchain& tools, const std::wstring& path, double targetMb) {
    const auto targetBytes = TargetBytes(targetMb);
    const auto outputSuffix = FitUnderSuffix(targetMb);
    const auto kind = ClassifyMedia(path);
    if (kind == MediaKind::Image) {
        return FitImageUnder(tools, path, targetBytes, outputSuffix);
    }
    if (kind == MediaKind::Video) {
        return FitVideoUnder(tools, path, targetBytes, outputSuffix);
    }
    throw std::runtime_error("Fit Under supports images and videos only");
}

} // namespace filedone
