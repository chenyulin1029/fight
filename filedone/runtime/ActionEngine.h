#pragma once
#include "Toolchain.h"
#include <string>
#include <vector>

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
ActionResult ExecuteSafeShare(const Toolchain& tools, const std::wstring& path);
ActionResult ExecuteMakePdf(const Toolchain& tools, const std::vector<std::wstring>& paths);
ActionResult ExecuteFitUnder(const Toolchain& tools, const std::wstring& path, double targetMb);

} // namespace filedone
