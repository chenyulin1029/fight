#include "TestHarness.h"
#include "../runtime/RuntimeTypes.h"
#include "../runtime/RequestFile.h"

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
    try {
        (void)filedone::ReadRequestFile(path.wstring());
    } catch (...) {
        threw = true;
    }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsBlankLine() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_Blank.fdreq");
    WriteUtf16Request(path, {L"smaller", L"", L"C:\\x.jpg"});
    bool threw = false;
    try {
        (void)filedone::ReadRequestFile(path.wstring());
    } catch (...) {
        threw = true;
    }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsEmptySelection() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_Empty.fdreq");
    WriteUtf16Request(path, {L"compatible"});
    bool threw = false;
    try {
        (void)filedone::ReadRequestFile(path.wstring());
    } catch (...) {
        threw = true;
    }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

void TestRequestRejectsUnknownAction() {
    auto path = TempRequestPath(L"FileDone_Runtime_Request_BadAction.fdreq");
    WriteUtf16Request(path, {L"MakePdf", L"C:\\x.jpg"});
    bool threw = false;
    try {
        (void)filedone::ReadRequestFile(path.wstring());
    } catch (...) {
        threw = true;
    }
    TEST_TRUE(threw);
    std::filesystem::remove(path);
}

} // namespace

int main() {
    TestActionTokens();
    TestRequestOrderAndUnicode();
    TestRequestRejectsMissingBom();
    TestRequestRejectsBlankLine();
    TestRequestRejectsEmptySelection();
    TestRequestRejectsUnknownAction();
    return test::Finish();
}
