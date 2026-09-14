#include "RequestFile.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <vector>

namespace filedone {
namespace {

std::vector<std::wstring> SplitLines(const std::wstring& text) {
    std::vector<std::wstring> lines;
    size_t start = 0;
    while (start <= text.size()) {
        size_t end = text.find(L'\n', start);
        std::wstring line = end == std::wstring::npos
            ? text.substr(start)
            : text.substr(start, end - start);
        if (!line.empty() && line.back() == L'\r') {
            line.pop_back();
        }
        lines.push_back(std::move(line));
        if (end == std::wstring::npos) break;
        start = end + 1;
    }

    if (!lines.empty() && lines.back().empty()) {
        lines.pop_back();
    }
    return lines;
}

} // namespace

Request ReadRequestFile(const std::wstring& path) {
    std::ifstream in(std::filesystem::path(path), std::ios::binary);
    if (!in) throw std::runtime_error("request open failed");

    std::vector<unsigned char> bytes(
        (std::istreambuf_iterator<char>(in)),
        std::istreambuf_iterator<char>());

    if (bytes.size() < 4) throw std::runtime_error("request too small");
    if (bytes[0] != 0xFF || bytes[1] != 0xFE) {
        throw std::runtime_error("request must be UTF-16LE with BOM");
    }
    if (((bytes.size() - 2) % 2) != 0) {
        throw std::runtime_error("request UTF-16 payload has odd byte count");
    }

    const size_t charCount = (bytes.size() - 2) / 2;
    std::wstring text;
    text.resize(charCount);
    if (charCount != 0) {
        std::memcpy(text.data(), bytes.data() + 2, charCount * sizeof(wchar_t));
    }

    auto lines = SplitLines(text);
    if (lines.empty() || lines[0].empty()) {
        throw std::runtime_error("request action missing");
    }

    auto action = ParseActionToken(lines[0]);
    if (!action.has_value()) {
        throw std::runtime_error("request action invalid");
    }

    Request request{*action, {}};
    for (size_t i = 1; i < lines.size(); ++i) {
        if (lines[i].empty()) {
            throw std::runtime_error("request contains blank path line");
        }
        request.paths.push_back(lines[i]);
    }

    if (request.paths.empty()) {
        throw std::runtime_error("request selection empty");
    }

    return request;
}

} // namespace filedone
