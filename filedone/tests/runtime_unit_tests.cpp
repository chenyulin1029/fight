#include "TestHarness.h"
#include "../runtime/RuntimeTypes.h"
#include "../runtime/RequestFile.h"
#include "../runtime/PathPolicy.h"
#include "../runtime/ActionMutex.h"
#include "../runtime/ProcessRunner.h"
#include "../runtime/Toolchain.h"
#include "../runtime/MediaProbe.h"

#include <windows.h>
#include <shellapi.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::filesystem::path TempRequestPath(const wchar_t* name) {
    wchar_t buffer[MAX_PATH]{};
    DWORD n = GetTempPathW(MAX_PATH, buffer);
    if (n == 0 || n >= MAX_PATH) throw std::runtime_error("GetTempPathW failed");
    return std::filesystem::path(buffer) / name;
}

std::filesystem::path TempCaseDirectory(const wchar_t* stem) {
    wchar_t buffer[MAX_PATH]{};
    DWORD n = GetTempPathW(MAX_PATH, buffer);
    if (n == 0 || n >= MAX_PATH) throw std::runtime_error("GetTempPathW failed");
    auto dir = std::filesystem::path(buffer) /
        (std::wstring(stem) + L"_" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(dir);
    std::filesystem::create_directories(dir);
    return dir;
}

void Touch(const std::filesystem::path& path) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("cannot create fixture");
    out.put('x');
}

std::wstring FindOnPath(const wchar_t* name) {
    wchar_t buffer[32768]{};
    DWORD n = SearchPathW(nullptr, name, nullptr, static_cast<DWORD>(std::size(buffer)), buffer, nullptr);
    if (n == 0 || n >= std::size(buffer)) return L"";
    return std::wstring(buffer, n);
}

void WriteUtf16Request(const std::filesystem::path& path, const std::vector<std::wstring>& lines, bool withBom = true) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("cannot create request fixture");
    if (withBom) {
        const unsigned char bom[2] = {0xFF, 0xFE};
        out.write(reinterpret_cast<const char*>(bom), 2);
    }
    for (const auto& line : lines) {
        out.write(reinterpret_cast<const char*>(line.data()), static_cast<std::streamsize>(line.size() * sizeof(wchar_t)));
        const wchar_t crlf[] = L"\r\n";
        out.write(reinterpret_cast<const char*>(crlf), static_cast<std::streamsize>(2 * sizeof(wchar_t)));
    }
}

void TestActionTokens() {
    TEST_EQ(*filedone::ParseActionToken(L"compatible"), filedone::Action::Compatible);
    TEST_EQ(*filedone::ParseActionToken(L"smaller"), filedone::Action::Smaller);
    TEST_EQ(*filedone::ParseActionToken(L"fitunder"), filedone::Action::FitUnder);
    TEST_EQ(*filedone::ParseActionToken(L"safeshare"), filedone::Action::SafeShare);
    TEST_EQ(*filedone::ParseActionToken(L"makepdf"), filedone::Action::MakePdf);
    TEST_FALSE(filedone::ParseActionToken(L"MakePdf").has_value());
    TEST_FALSE(filedone::ParseActionToken(L"unknown").has_value());
}

void TestRequestOrderAndUnicode() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_Unicode.fdreq");
    WriteUtf16Request(path, {
        L"makepdf",
        L"C:\\測試\\01 中文 空格.jpg",
        L"C:\\測試\\02_日本語_😀.png"
    });

    auto req = filedone::ReadRequestFile(path.wstring());
    TEST_EQ(req.action, filedone::Action::MakePdf);
    TEST_EQ(req.paths.size(), static_cast<size_t>(2));
    TEST_EQ(req.paths[0], std::wstring(L"C:\\測試\\01 中文 空格.jpg"));
    TEST_EQ(req.paths[1], std::wstring(L"C:\\測試\\02_日本語_😀.png"));
    std::filesystem::remove(path);
}

void TestRequestRejectsMissingBom() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_NoBom.fdreq");
    WriteUtf16Request(path, {L"smaller", L"C:\\x.jpg"}, false);
    bool threw = false;
    try { (void)filedone::ReadRequestFile(path.wstring()); } catch (...) { threw = true; }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsBlankLine() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_Blank.fdreq");
    WriteUtf16Request(path, {L"smaller", L"", L"C:\\x.jpg"});
    bool threw = false;
    try { (void)filedone::ReadRequestFile(path.wstring()); } catch (...) { threw = true; }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsEmptySelection() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_Empty.fdreq");
    WriteUtf16Request(path, {L"compatible"});
    bool threw = false;
    try { (void)filedone::ReadRequestFile(path.wstring()); } catch (...) { threw = true; }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsUnknownAction() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_BadAction.fdreq");
    WriteUtf16Request(path, {L"MakePdf", L"C:\\x.jpg"});
    bool threw = false;
    try { (void)filedone::ReadRequestFile(path.wstring()); } catch (...) { threw = true; }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestMediaClassification() {
    TEST_EQ(filedone::ClassifyMedia(L"C:\\x.JPG"), filedone::MediaKind::Image);
    TEST_EQ(filedone::ClassifyMedia(L"C:\\x.HeIc"), filedone::MediaKind::Image);
    TEST_EQ(filedone::ClassifyMedia(L"C:\\x.MP4"), filedone::MediaKind::Video);
    TEST_EQ(filedone::ClassifyMedia(L"C:\\x.OpUs"), filedone::MediaKind::Audio);
    TEST_EQ(filedone::ClassifyMedia(L"C:\\x.txt"), filedone::MediaKind::Unsupported);
}

void TestUniqueOutputNaming() {
    auto dir = TempCaseDirectory(L"FileDone_PathPolicy");
    auto input = dir / L"photo.jpg";
    Touch(input);
    Touch(dir / L"photo_smaller.jpg");

    auto second = filedone::UniqueOutputPath(input.wstring(), L"_smaller", L".jpg");
    TEST_EQ(std::filesystem::path(second).filename().wstring(), std::wstring(L"photo_smaller_2.jpg"));

    Touch(dir / L"photo_smaller_2.jpg");
    auto third = filedone::UniqueOutputPath(input.wstring(), L"_smaller", L"jpg");
    TEST_EQ(std::filesystem::path(third).filename().wstring(), std::wstring(L"photo_smaller_3.jpg"));
    std::filesystem::remove_all(dir);
}

void TestActionMutexNameMatchesP152() {
    std::vector<std::wstring> paths{L"C:\\DATA\\A.JPG"};
    auto name = filedone::BuildActionMutexName(filedone::Action::Compatible, paths);
    TEST_EQ(name, std::wstring(L"Local\\FileDone_Action_DB0C8B3E2E5520FA1818A5EAE39591D8A64C5AD785933E9F4CEC1F57FABEE07F"));

    std::vector<std::wstring> lower{L"c:\\data\\a.jpg"};
    TEST_EQ(filedone::BuildActionMutexName(filedone::Action::Compatible, lower), name);
    TEST_FALSE(filedone::BuildActionMutexName(filedone::Action::Smaller, lower) == name);
}

void TestWindowsArgumentQuotingRoundTrips() {
    const std::wstring exe = L"C:\\Program Files\\FileDone\\fixture.exe";
    const std::vector<std::wstring> args{
        L"plain",
        L"with space",
        L"quote\"inside",
        L"trail\\",
        L"",
        L"中文 日本語 😀",
        L"a&b(c)"
    };
    auto commandLine = filedone::BuildWindowsCommandLine(exe, args);
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(commandLine.c_str(), &argc);
    TEST_TRUE(argv != nullptr);
    if (!argv) return;
    TEST_EQ(argc, static_cast<int>(args.size() + 1));
    TEST_EQ(std::wstring(argv[0]), exe);
    for (size_t i = 0; i < args.size(); ++i) {
        TEST_EQ(std::wstring(argv[i + 1]), args[i]);
    }
    LocalFree(argv);
}

void TestProcessRunnerCapturesOutput() {
    auto whereExe = FindOnPath(L"where.exe");
    TEST_FALSE(whereExe.empty());
    if (whereExe.empty()) return;
    auto result = filedone::RunProcess(whereExe, {L"cmd.exe"});
    TEST_EQ(result.exitCode, static_cast<DWORD>(0));
    auto text = result.stdoutText;
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
        return static_cast<char>(c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c);
    });
    TEST_TRUE(text.find("cmd.exe") != std::string::npos);
}

void TestToolchainOverride() {
    auto dir = TempCaseDirectory(L"FileDone_Toolchain");
    Touch(dir / L"ffmpeg.exe");
    Touch(dir / L"ffprobe.exe");
    Touch(dir / L"magick.exe");
    TEST_TRUE(SetEnvironmentVariableW(L"FILEDONE_TOOLS_DIR", dir.c_str()) != FALSE);
    auto tools = filedone::Toolchain::FromRuntimeDirectory();
    TEST_EQ(std::filesystem::path(tools.ffmpeg).filename().wstring(), std::wstring(L"ffmpeg.exe"));
    TEST_EQ(std::filesystem::path(tools.ffprobe).filename().wstring(), std::wstring(L"ffprobe.exe"));
    TEST_EQ(std::filesystem::path(tools.magick).filename().wstring(), std::wstring(L"magick.exe"));
    SetEnvironmentVariableW(L"FILEDONE_TOOLS_DIR", nullptr);
    std::filesystem::remove_all(dir);
}

void TestImageProbeSmoke() {
    auto magick = FindOnPath(L"magick.exe");
    TEST_FALSE(magick.empty());
    if (magick.empty()) return;

    auto dir = TempCaseDirectory(L"FileDone_ImageProbe");
    auto image = dir / L"opaque.png";
    auto create = filedone::RunProcess(magick, {L"-size", L"16x8", L"xc:red", image.wstring()});
    TEST_EQ(create.exitCode, static_cast<DWORD>(0));

    filedone::Toolchain tools{};
    tools.magick = magick;
    TEST_TRUE(filedone::ImageIsOpaque(tools, image.wstring()));
    auto size = filedone::GetImageSize(tools, image.wstring());
    TEST_EQ(size.width, 16);
    TEST_EQ(size.height, 8);
    std::filesystem::remove_all(dir);
}

void TestVideoProbeSmoke() {
    auto ffmpeg = FindOnPath(L"ffmpeg.exe");
    auto ffprobe = FindOnPath(L"ffprobe.exe");
    TEST_FALSE(ffmpeg.empty());
    TEST_FALSE(ffprobe.empty());
    if (ffmpeg.empty() || ffprobe.empty()) return;

    auto dir = TempCaseDirectory(L"FileDone_VideoProbe");
    auto video = dir / L"probe.mp4";
    auto create = filedone::RunProcess(ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"color=c=black:s=32x24:d=1",
        L"-c:v", L"mpeg4", video.wstring()
    });
    TEST_EQ(create.exitCode, static_cast<DWORD>(0));

    filedone::Toolchain tools{};
    tools.ffmpeg = ffmpeg;
    tools.ffprobe = ffprobe;
    auto info = filedone::GetVideoInfo(tools, video.wstring());
    TEST_TRUE(info.duration > 0.5);
    TEST_EQ(info.videoCodec, std::string("mpeg4"));
    TEST_TRUE(info.audioCodec.empty());
    std::filesystem::remove_all(dir);
}

} // namespace

int main() {
    TestActionTokens();
    TestRequestOrderAndUnicode();
    TestRequestRejectsMissingBom();
    TestRequestRejectsBlankLine();
    TestRequestRejectsEmptySelection();
    TestRequestRejectsUnknownAction();
    TestMediaClassification();
    TestUniqueOutputNaming();
    TestActionMutexNameMatchesP152();
    TestWindowsArgumentQuotingRoundTrips();
    TestProcessRunnerCapturesOutput();
    TestToolchainOverride();
    TestImageProbeSmoke();
    TestVideoProbeSmoke();
    return test::Finish();
}
