#include "../TestHarness.h"
#include "../../runtime/ActionEngine.h"
#include "../../runtime/MediaProbe.h"
#include "../../runtime/ProcessRunner.h"
#include "../../runtime/Toolchain.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::wstring FindOnPath(const wchar_t* name) {
    wchar_t buffer[32768]{};
    DWORD n = SearchPathW(nullptr, name, nullptr, static_cast<DWORD>(std::size(buffer)), buffer, nullptr);
    if (n == 0 || n >= std::size(buffer)) return L"";
    return std::wstring(buffer, n);
}

std::filesystem::path TestRoot() {
    wchar_t buffer[MAX_PATH]{};
    DWORD n = GetTempPathW(MAX_PATH, buffer);
    if (n == 0 || n >= MAX_PATH) throw std::runtime_error("GetTempPathW failed");
    auto root = std::filesystem::path(buffer) /
        (L"FileDone_ActionEngine_" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    return root;
}

void RequireOk(const filedone::ProcessResult& result) {
    if (result.exitCode != 0) {
        throw std::runtime_error("fixture tool failed: " + result.stderrText);
    }
}

void RequireFile(const std::wstring& path) {
    TEST_TRUE(std::filesystem::is_regular_file(path));
    if (std::filesystem::is_regular_file(path)) {
        TEST_TRUE(std::filesystem::file_size(path) > 0);
    }
}

filedone::Toolchain ResolveTools() {
    filedone::Toolchain tools{};
    tools.magick = FindOnPath(L"magick.exe");
    tools.ffmpeg = FindOnPath(L"ffmpeg.exe");
    tools.ffprobe = FindOnPath(L"ffprobe.exe");
    if (tools.magick.empty() || tools.ffmpeg.empty() || tools.ffprobe.empty()) {
        throw std::runtime_error("integration tools missing");
    }
    return tools;
}

void TestCompatibleAndSmaller() {
    const auto tools = ResolveTools();
    const auto root = TestRoot();

    const auto jpg = root / L"already compatible.jpg";
    RequireOk(filedone::RunProcess(tools.magick, {L"-size", L"48x32", L"xc:red", jpg.wstring()}));
    auto jpgNoop = filedone::ExecuteCompatible(tools, jpg.wstring());
    TEST_EQ(jpgNoop.outcome, filedone::ActionOutcome::Noop);
    TEST_TRUE(jpgNoop.outputPath.empty());

    const auto opaqueWebp = root / L"opaque.webp";
    RequireOk(filedone::RunProcess(tools.magick, {L"-size", L"64x40", L"xc:blue", opaqueWebp.wstring()}));
    auto opaqueCompatible = filedone::ExecuteCompatible(tools, opaqueWebp.wstring());
    TEST_EQ(opaqueCompatible.outcome, filedone::ActionOutcome::Pass);
    TEST_EQ(std::filesystem::path(opaqueCompatible.outputPath).extension().wstring(), std::wstring(L".jpg"));
    RequireFile(opaqueCompatible.outputPath);

    const auto alpha = root / L"alpha.png";
    RequireOk(filedone::RunProcess(tools.magick, {
        L"-size", L"64x40", L"xc:none", L"-fill", L"#4488CC88",
        L"-draw", L"rectangle 4,4 50,30", alpha.wstring()
    }));
    auto alphaWebp = root / L"alpha.webp";
    RequireOk(filedone::RunProcess(tools.magick, {alpha.wstring(), alphaWebp.wstring()}));
    auto alphaCompatible = filedone::ExecuteCompatible(tools, alphaWebp.wstring());
    TEST_EQ(std::filesystem::path(alphaCompatible.outputPath).extension().wstring(), std::wstring(L".png"));
    RequireFile(alphaCompatible.outputPath);

    const auto animatedWebp = root / L"animated.webp";
    RequireOk(filedone::RunProcess(tools.magick, {
        L"-size", L"24x24", L"xc:red", L"-delay", L"10",
        L"-size", L"24x24", L"xc:blue", L"-delay", L"10",
        L"-loop", L"0", animatedWebp.wstring()
    }));
    bool animatedFailed = false;
    try { (void)filedone::ExecuteCompatible(tools, animatedWebp.wstring()); }
    catch (...) { animatedFailed = true; }
    TEST_TRUE(animatedFailed);

    const auto h264 = root / L"already.mp4";
    RequireOk(filedone::RunProcess(tools.ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"color=c=black:s=64x48:d=1",
        L"-c:v", L"libx264", L"-pix_fmt", L"yuv420p", h264.wstring()
    }));
    auto videoNoop = filedone::ExecuteCompatible(tools, h264.wstring());
    TEST_EQ(videoNoop.outcome, filedone::ActionOutcome::Noop);

    const auto avi = root / L"legacy.avi";
    RequireOk(filedone::RunProcess(tools.ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"color=c=black:s=64x48:d=1",
        L"-c:v", L"mpeg4", avi.wstring()
    }));
    auto videoCompatible = filedone::ExecuteCompatible(tools, avi.wstring());
    RequireFile(videoCompatible.outputPath);
    TEST_EQ(std::filesystem::path(videoCompatible.outputPath).extension().wstring(), std::wstring(L".mp4"));
    TEST_EQ(filedone::GetVideoInfo(tools, videoCompatible.outputPath).videoCodec, std::string("h264"));

    const auto wav = root / L"tone.wav";
    RequireOk(filedone::RunProcess(tools.ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"sine=frequency=440:duration=1", wav.wstring()
    }));
    auto audioCompatible = filedone::ExecuteCompatible(tools, wav.wstring());
    RequireFile(audioCompatible.outputPath);
    TEST_EQ(std::filesystem::path(audioCompatible.outputPath).extension().wstring(), std::wstring(L".mp3"));

    const auto largeOpaque = root / L"large opaque.png";
    RequireOk(filedone::RunProcess(tools.magick, {L"-size", L"3000x1800", L"gradient:", largeOpaque.wstring()}));
    auto smallerOpaque = filedone::ExecuteSmaller(tools, largeOpaque.wstring());
    RequireFile(smallerOpaque.outputPath);
    TEST_EQ(std::filesystem::path(smallerOpaque.outputPath).extension().wstring(), std::wstring(L".jpg"));
    auto smallerDims = filedone::GetImageSize(tools, smallerOpaque.outputPath);
    TEST_TRUE(smallerDims.width <= 2560);
    TEST_TRUE(smallerDims.height <= 2560);

    auto smallerAlpha = filedone::ExecuteSmaller(tools, alpha.wstring());
    RequireFile(smallerAlpha.outputPath);
    TEST_EQ(std::filesystem::path(smallerAlpha.outputPath).extension().wstring(), std::wstring(L".webp"));

    auto smallerVideo = filedone::ExecuteSmaller(tools, avi.wstring());
    RequireFile(smallerVideo.outputPath);
    TEST_EQ(filedone::GetVideoInfo(tools, smallerVideo.outputPath).videoCodec, std::string("h264"));

    auto smallerAudio = filedone::ExecuteSmaller(tools, wav.wstring());
    RequireFile(smallerAudio.outputPath);
    TEST_EQ(std::filesystem::path(smallerAudio.outputPath).extension().wstring(), std::wstring(L".mp3"));

    const auto unsupported = root / L"x.txt";
    { std::ofstream out(unsupported); out << "x"; }
    bool unsupportedFailed = false;
    try { (void)filedone::ExecuteSmaller(tools, unsupported.wstring()); }
    catch (...) { unsupportedFailed = true; }
    TEST_TRUE(unsupportedFailed);

    std::filesystem::remove_all(root);
}

} // namespace

int main() {
    TestCompatibleAndSmaller();
    return test::Finish();
}
