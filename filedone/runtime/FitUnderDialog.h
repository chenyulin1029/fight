#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <optional>
#include <string>

namespace filedone {

std::optional<double> ParseTargetMbText(
    const std::wstring& text,
    const std::wstring& localDecimalSeparator);

std::optional<double> PromptTargetMb(HWND owner);

} // namespace filedone
