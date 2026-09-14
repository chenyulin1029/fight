#pragma once
#include <optional>
#include <string_view>

namespace filedone {

enum class Action {
    Compatible,
    Smaller,
    FitUnder,
    SafeShare,
    MakePdf
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
