#pragma once
#include "Toolchain.h"
#include <string>

namespace filedone {

enum class ActionOutcome {
    Pass,
    Noop
};

struct ActionResult {
    ActionOutcome outcome = ActionOutcome::Pass;
    std::wstring outputPath;
    std::string internalNote;
};

ActionResult ExecuteCompatible(const Toolchain& tools, const std::wstring& path);
ActionResult ExecuteSmaller(const Toolchain& tools, const std::wstring& path);

} // namespace filedone
