#pragma once
#include "RuntimeTypes.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>

namespace filedone {

std::wstring BuildActionMutexName(
    Action action,
    const std::vector<std::wstring>& canonicalPaths);

class ActionMutex {
public:
    ActionMutex(Action action, const std::vector<std::wstring>& canonicalPaths);
    ~ActionMutex();

    ActionMutex(const ActionMutex&) = delete;
    ActionMutex& operator=(const ActionMutex&) = delete;
    ActionMutex(ActionMutex&& other) noexcept;
    ActionMutex& operator=(ActionMutex&& other) noexcept;

    bool acquired() const noexcept { return acquired_; }

private:
    HANDLE handle_ = nullptr;
    bool acquired_ = false;
};

} // namespace filedone
