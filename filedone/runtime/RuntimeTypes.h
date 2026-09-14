#pragma once
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace filedone {

enum class Action {
    Compatible,
    Smaller,
    FitUnder,
    SafeShare,
    MakePdf
};

struct Request {
    Action action;
    std::vector<std::wstring> paths;
};

inline std::optional<Action> ParseActionToken(std::wstring_view token) {
    if (token == L"compatible") return Action::Compatible;
    if (token == L"smaller") return Action::Smaller;
    if (token == L"fitunder") return Action::FitUnder;
    if (token == L"safeshare") return Action::SafeShare;
    if (token == L"makepdf") return Action::MakePdf;
    return std::nullopt;
}

} // namespace filedone
