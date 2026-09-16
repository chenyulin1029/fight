#include "../TestHarness.h"
#include "../../runtime/ActionEngine.h"
#include "../../runtime/MediaProbe.h"
#include "../../runtime/ProcessRunner.h"
#include "../../runtime/Toolchain.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace {

std::wstring FindOnPath(const wchar_t* name) {
    wchar_t buffer[32768]{};
    DWORD n = SearchPathW(nullptr, name, nullptr, static_cast<DWORD>(std::size(buffer)), buffer, nullptr);
    if (n == 0 || n >= std::size(buffer)) return L"";
    return std::wstring(buffer, n);
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

std::filesystem::path TestRoot() {
    wchar_t buffer[MAX_PATH]{};
    DWORD n = GetTempPathW(MAX_PATH, buffer);
    if (n == 0 || n >= MAX_PATH) throw std::runtime_error("GetTempPathW failed");
    auto root = std::filesystem::path(buffer) /
        (L"FileDone_FitUnder_" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    return root;
}

void RequireOk(const filedone::ProcessResult& result) {
    if (result.exitCode != 0) {
        throw std::runtime_error("fixture tool failed: " + result.stderrText);
    }
}

std::uintmax_t TargetBytes(double targetMb) {
    return static_cast<std::uintmax_t>(std::floor(targetMb * 1024.0 * 1024.0));
}

void RequireStrictFit(const std::wstring& output, double targetMb) {
    TEST_TRUE(std::filesystem::is_regular_file(output));
    if (!std::filesystem::is_regular_file(output)) return;
    const auto bytes = std::filesystem::file_size(output);
    TEST_TRUE(bytes > 0);
    TEST_TRUE(bytes <= TargetBytes(targetMb));
}

void TestStrictImageFitUnder() {
    const auto tools = ResolveTools();
    const auto root = TestRoot();

    const auto opaque = root / L"高細節 opaque.png";
    RequireOk(filedone::RunProcess(tools.magick, {
        L"-size", L"1800x1200", L"plasma:fractal", L"-colorspace", L"sRGB", opaque.wstring()
    }));
    const auto sourceOpaqueBytes = std::filesystem::file_size(opaque);
    const double opaqueTargetMb = 0.12;
    TEST_TRUE(sourceOpaqueBytes > TargetBytes(opaqueTargetMb));

    auto opaqueResult = filedone::ExecuteFitUnder(tools, opaque.wstring(), opaqueTargetMb);
    TEST_EQ(opaqueResult.outcome, filedone::ActionOutcome::Pass);
    TEST_EQ(std::filesystem::path(opaqueResult.outputPath).extension().wstring(), std::wstring(L".jpg"));
    RequireStrictFit(opaqueResult.outputPath, opaqueTargetMb);
    TEST_EQ(std::filesystem::file_size(opaque), sourceOpaqueBytes);

    const auto alpha = root / L"透明 alpha.png";
    RequireOk(filedone::RunProcess(tools.magick, {
        L"-size", L"1600x1200", L"xc:none",
        L"-fill", L"#1A4FD0AA", L"-draw", L"rectangle 0,0 1599,1199",
        L"-fill", L"#FF884488", L"-draw", L"circle 800,600 1200,600",
        L"-fill", L"#33CC77CC", L"-draw", L"rectangle 120,150 1480,1050",
        alpha.wstring()
    }));
    const double alphaTargetMb = 0.08;
    auto alphaResult = filedone::ExecuteFitUnder(tools, alpha.wstring(), alphaTargetMb);
    TEST_EQ(alphaResult.outcome, filedone::ActionOutcome::Pass);
    TEST_EQ(std::filesystem::path(alphaResult.outputPath).extension().wstring(), std::wstring(L".webp"));
    RequireStrictFit(alphaResult.outputPath, alphaTargetMb);

    bool badTargetFailed = false;
    try { (void)filedone::ExecuteFitUnder(tools, opaque.wstring(), 0.0); }
    catch (...) { badTargetFailed = true; }
    TEST_TRUE(badTargetFailed);

    std::filesystem::remove_all(root);
}

void TestStrictVideoFitUnder() {
    const auto tools = ResolveTools();
    const auto root = TestRoot();

    const auto input = root / L"測試 video source.mp4";
    RequireOk(filedone::RunProcess(tools.ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"testsrc2=size=640x360:rate=30:duration=3",
        L"-f", L"lavfi", L"-i", L"sine=frequency=523:sample_rate=48000:duration=3",
        L"-c:v", L"libx264", L"-preset", L"ultrafast", L"-crf", L"12",
        L"-pix_fmt", L"yuv420p",
        L"-c:a", L"aac", L"-b:a", L"128k",
        L"-shortest", input.wstring()
    }));

    const auto originalBytes = std::filesystem::file_size(input);
    const double targetMb = 0.30;
    TEST_TRUE(originalBytes > TargetBytes(targetMb));

    auto result = filedone::ExecuteFitUnder(tools, input.wstring(), targetMb);
    TEST_EQ(result.outcome, filedone::ActionOutcome::Pass);
    TEST_EQ(std::filesystem::path(result.outputPath).extension().wstring(), std::wstring(L".mp4"));
    RequireStrictFit(result.outputPath, targetMb);
    TEST_EQ(std::filesystem::file_size(input), originalBytes);

    const auto info = filedone::GetVideoInfo(tools, result.outputPath);
    TEST_EQ(info.videoCodec, std::string("h264"));
    TEST_EQ(info.audioCodec, std::string("aac"));

    std::filesystem::remove_all(root);
}

} // namespace

int main() {
    TestStrictImageFitUnder();
    TestStrictVideoFitUnder();
    return test::Finish();
}
