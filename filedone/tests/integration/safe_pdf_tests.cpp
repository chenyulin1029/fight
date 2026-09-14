#include "../TestHarness.h"
#include "../../runtime/ActionEngine.h"
#include "../../runtime/ProcessRunner.h"
#include "../../runtime/Toolchain.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <regex>
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

std::filesystem::path Root() {
    wchar_t buffer[MAX_PATH]{};
    DWORD n = GetTempPathW(MAX_PATH, buffer);
    if (n == 0 || n >= MAX_PATH) throw std::runtime_error("GetTempPathW failed");
    auto root = std::filesystem::path(buffer) /
        (L"FileDone_SafePdf_" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    return root;
}

void RequireOk(const filedone::ProcessResult& result) {
    if (result.exitCode != 0) throw std::runtime_error("fixture command failed: " + result.stderrText);
}

void RequireFile(const std::wstring& path) {
    TEST_TRUE(std::filesystem::is_regular_file(path));
    if (std::filesystem::is_regular_file(path)) TEST_TRUE(std::filesystem::file_size(path) > 0);
}

std::string Trim(std::string value) {
    while (!value.empty() && (value.back() == '\r' || value.back() == '\n' || value.back() == ' ' || value.back() == '\t')) value.pop_back();
    size_t first = 0;
    while (first < value.size() && (value[first] == '\r' || value[first] == '\n' || value[first] == ' ' || value[first] == '\t')) ++first;
    return value.substr(first);
}

int PdfPageCount(const std::wstring& path) {
    std::ifstream in(std::filesystem::path(path), std::ios::binary);
    std::string bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    const std::regex pageRegex(R"(/Type\s*/Page(?!s)\b)");
    return static_cast<int>(std::distance(
        std::sregex_iterator(bytes.begin(), bytes.end(), pageRegex),
        std::sregex_iterator()));
}

void TestSafeShareAndPdf() {
    const auto tools = ResolveTools();
    const auto root = Root();

    const auto seededPng = root / L"seeded.png";
    RequireOk(filedone::RunProcess(tools.magick, {
        L"-size", L"40x30", L"xc:orange", L"-set", L"comment", L"FILEDONE_SECRET", seededPng.wstring()
    }));
    auto safePng = filedone::ExecuteSafeShare(tools, seededPng.wstring());
    RequireFile(safePng.outputPath);
    TEST_EQ(std::filesystem::path(safePng.outputPath).extension().wstring(), std::wstring(L".png"));
    auto commentProbe = filedone::RunProcess(tools.magick, {
        L"identify", L"-quiet", L"-format", L"%[comment]", safePng.outputPath
    });
    TEST_EQ(commentProbe.exitCode, static_cast<DWORD>(0));
    TEST_TRUE(commentProbe.stdoutText.find("FILEDONE_SECRET") == std::string::npos);

    const auto fakeHeic = root / L"camera.heic";
    std::filesystem::copy_file(seededPng, fakeHeic, std::filesystem::copy_options::overwrite_existing);
    auto safeHeic = filedone::ExecuteSafeShare(tools, fakeHeic.wstring());
    RequireFile(safeHeic.outputPath);
    TEST_EQ(std::filesystem::path(safeHeic.outputPath).extension().wstring(), std::wstring(L".jpg"));

    const auto taggedMp4 = root / L"tagged.mp4";
    RequireOk(filedone::RunProcess(tools.ffmpeg, {
        L"-hide_banner", L"-loglevel", L"error", L"-y",
        L"-f", L"lavfi", L"-i", L"color=c=black:s=64x48:d=1",
        L"-c:v", L"libx264", L"-pix_fmt", L"yuv420p",
        L"-metadata", L"title=FILEDONE_SECRET", taggedMp4.wstring()
    }));
    auto safeVideo = filedone::ExecuteSafeShare(tools, taggedMp4.wstring());
    RequireFile(safeVideo.outputPath);
    TEST_EQ(std::filesystem::path(safeVideo.outputPath).extension().wstring(), std::wstring(L".mp4"));
    auto titleProbe = filedone::RunProcess(tools.ffprobe, {
        L"-v", L"error", L"-show_entries", L"format_tags=title",
        L"-of", L"default=noprint_wrappers=1:nokey=1", safeVideo.outputPath
    });
    TEST_EQ(titleProbe.exitCode, static_cast<DWORD>(0));
    TEST_TRUE(Trim(titleProbe.stdoutText).empty());

    std::vector<std::wstring> pages;
    const wchar_t* colors[] = {L"red", L"green", L"blue"};
    for (int i = 0; i < 3; ++i) {
        auto p = root / (std::to_wstring(i + 1) + L" page.png");
        RequireOk(filedone::RunProcess(tools.magick, {L"-size", L"50x40", std::wstring(L"xc:") + colors[i], p.wstring()}));
        pages.push_back(p.wstring());
    }
    auto pdf = filedone::ExecuteMakePdf(tools, pages);
    RequireFile(pdf.outputPath);
    TEST_EQ(std::filesystem::path(pdf.outputPath).filename().wstring(), std::wstring(L"1 page_document.pdf"));
    TEST_EQ(PdfPageCount(pdf.outputPath), 3);

    const auto unsupported = root / L"bad.txt";
    { std::ofstream out(unsupported); out << "x"; }
    bool pdfRejected = false;
    try { (void)filedone::ExecuteMakePdf(tools, {pages[0], unsupported.wstring()}); }
    catch (...) { pdfRejected = true; }
    TEST_TRUE(pdfRejected);

    std::filesystem::remove_all(root);
}

} // namespace

int main() {
    TestSafeShareAndPdf();
    return test::Finish();
}
