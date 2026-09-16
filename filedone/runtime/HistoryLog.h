#pragma once

#include <string>
#include <vector>

namespace filedone {

void AppendHistoryLog(
    const std::string& action,
    const std::vector<std::wstring>& inputs,
    const std::wstring& output,
    const std::string& status,
    const std::string& detail) noexcept;

} // namespace filedone
