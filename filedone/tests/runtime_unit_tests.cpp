#include "TestHarness.h"
#include "../runtime/RuntimeTypes.h"
#include "../runtime/RequestFile.h"
#include "../runtime/PathPolicy.h"
#include "../runtime/ActionMutex.h"

#include <windows.h>
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
    return test::Finish();
}
