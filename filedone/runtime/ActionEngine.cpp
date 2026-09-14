#include "ActionEngine.h"
#include "MediaProbe.h"
#include "PathPolicy.h"
#include "ProcessRunner.h"

#include <algorithm>
#include <filesystem>
#include <stdexcept>
#include <string>
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

ActionResult Pass(std::wstring output, std::string note = {}) {
    return ActionResult{ActionOutcome::Pass, std::move(output), std::move(note)};
}

ActionResult Noop(std::string note) {
    return ActionResult{ActionOutcome::Noop, L"", std::move(note)};
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
        return Pass(output);
    }

    if (kind == MediaKind::Audio) {
        const auto output = UniqueOutputPath(path, L"_compatible", L".mp3");
        RunProducing(
            tools.ffmpeg,
            {L"-hide_banner", L"-loglevel", L"error", L"-y",
             L"-i", path, L"-vn", L"-c:a", L"libmp3lame", L"-b:a", L"192k", output},
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
        return Pass(output);
    }

    if (kind == MediaKind::Audio) {
        const auto output = UniqueOutputPath(path, L"_smaller", L".mp3");
        RunProducing(
            tools.ffmpeg,
            {L"-hide_banner", L"-loglevel", L"error", L"-y",
             L"-i", path, L"-vn", L"-c:a", L"libmp3lame", L"-b:a", L"128k", output},
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

} // namespace filedone
