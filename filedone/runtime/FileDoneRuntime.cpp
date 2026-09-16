#include "ActionEngine.h"
#include "ActionMutex.h"
#include "FitUnderDialog.h"
#include "HistoryLog.h"
#include "PathPolicy.h"
#include "RequestFile.h"
#include "RuntimeTypes.h"
#include "Toolchain.h"
#include "UserNotice.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>

#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace filedone {
namespace {

struct RuntimeOutcome {
    int exitCode = 1;
    std::string status;
    std::wstring output;
    std::string detail;
};

bool TestMode() noexcept {
    wchar_t buffer[8]{};
    const DWORD n = GetEnvironmentVariableW(
        L"FILEDONE_TEST_MODE",
        buffer,
        static_cast<DWORD>(std::size(buffer)));
    return n == 1 && buffer[0] == L'1';
}

std::string ActionToken(Action action) {
    switch (action) {
    case Action::Compatible: return "compatible";
    case Action::Smaller: return "smaller";
    case Action::FitUnder: return "fitunder";
    case Action::SafeShare: return "safeshare";
    case Action::MakePdf: return "makepdf";
    }
    return "unknown";
}

void DeleteRequest(const std::wstring& requestPath) noexcept {
    std::error_code ec;
    std::filesystem::remove(std::filesystem::path(requestPath), ec);
}

std::vector<std::wstring> ValidateAndCanonicalize(const std::vector<std::wstring>& paths) {
    std::vector<std::wstring> result;
    result.reserve(paths.size());
    for (const auto& path : paths) {
        if (path.empty()) throw std::runtime_error("empty input path");
        const std::wstring canonical = CanonicalPath(path);
        std::error_code ec;
        if (!std::filesystem::is_regular_file(std::filesystem::path(canonical), ec) || ec) {
            throw std::runtime_error("input file does not exist");
        }
        result.push_back(canonical);
    }
    if (result.empty()) throw std::runtime_error("empty selection");
    return result;
}

void VerifyResult(const ActionResult& result) {
    if (result.outcome == ActionOutcome::Noop) return;
    if (result.outputPath.empty()) throw std::runtime_error("action output path missing");

    std::error_code ec;
    const auto path = std::filesystem::path(result.outputPath);
    if (!std::filesystem::is_regular_file(path, ec) || ec) {
        throw std::runtime_error("action output missing");
    }
    const auto bytes = std::filesystem::file_size(path, ec);
    if (ec || bytes == 0) throw std::runtime_error("action output empty");
}

void AppendOutput(std::wstring& summary, const ActionResult& result) {
    if (result.outcome == ActionOutcome::Noop || result.outputPath.empty()) return;
    if (!summary.empty()) summary += L" | ";
    summary += result.outputPath;
}

RuntimeOutcome ExecuteValidated(
    const Request& request,
    const std::optional<double>& targetOverride) {

    const std::string token = ActionToken(request.action);
    std::wstring outputSummary;

    try {
        ActionMutex mutex(request.action, request.paths);
        if (!mutex.acquired()) throw std::runtime_error("action mutex unavailable");

        Toolchain tools;
        try {
            tools = Toolchain::FromRuntimeDirectory();
        } catch (const std::exception& error) {
            AppendHistoryLog(token, request.paths, L"", "runtime_unavailable", error.what());
            ShowRuntimeUnavailableNotice();
            return RuntimeOutcome{3, "runtime_unavailable", L"", error.what()};
        }

        try {
            if (request.action == Action::MakePdf) {
                const ActionResult result = ExecuteMakePdf(tools, request.paths);
                VerifyResult(result);
                AppendOutput(outputSummary, result);
            } else if (request.action == Action::FitUnder) {
                std::optional<double> target = targetOverride;
                if (!target.has_value()) target = PromptTargetMb(nullptr);
                if (!target.has_value()) {
                    AppendHistoryLog(token, request.paths, L"", "cancelled", "");
                    return RuntimeOutcome{0, "cancelled", L"", ""};
                }

                for (const auto& path : request.paths) {
                    const ActionResult result = ExecuteFitUnder(tools, path, *target);
                    VerifyResult(result);
                    AppendOutput(outputSummary, result);
                }
            } else {
                for (const auto& path : request.paths) {
                    ActionResult result;
                    switch (request.action) {
                    case Action::Compatible:
                        result = ExecuteCompatible(tools, path);
                        break;
                    case Action::Smaller:
                        result = ExecuteSmaller(tools, path);
                        break;
                    case Action::SafeShare:
                        result = ExecuteSafeShare(tools, path);
                        break;
                    case Action::FitUnder:
                    case Action::MakePdf:
                        throw std::runtime_error("invalid dispatcher action");
                    }
                    VerifyResult(result);
                    AppendOutput(outputSummary, result);
                }
            }

            AppendHistoryLog(token, request.paths, outputSummary, "success", "");
            return RuntimeOutcome{0, "success", outputSummary, ""};
        } catch (const std::exception& error) {
            AppendHistoryLog(token, request.paths, outputSummary, "failure", error.what());
            ShowOperationFailedNotice();
            return RuntimeOutcome{1, "failure", outputSummary, error.what()};
        }
    } catch (const std::exception& error) {
        AppendHistoryLog(token, request.paths, outputSummary, "failure", error.what());
        ShowOperationFailedNotice();
        return RuntimeOutcome{1, "failure", outputSummary, error.what()};
    }
}

int Run(int argc, wchar_t** argv) {
    if (argc != 2 && argc != 4) {
        ShowInvalidRequestNotice();
        return 2;
    }

    const std::wstring requestPath = argv[1] == nullptr ? L"" : argv[1];
    if (requestPath.empty()) {
        ShowInvalidRequestNotice();
        return 2;
    }

    std::optional<double> targetOverride;
    if (argc == 4) {
        if (!TestMode() || argv[2] == nullptr || std::wstring(argv[2]) != L"--target-mb" || argv[3] == nullptr) {
            AppendHistoryLog("invalid", {}, L"", "invalid_request", "test override rejected");
            ShowInvalidRequestNotice();
            DeleteRequest(requestPath);
            return 2;
        }
        targetOverride = ParseTargetMbText(argv[3], L".");
        if (!targetOverride.has_value()) {
            AppendHistoryLog("invalid", {}, L"", "invalid_request", "invalid target override");
            ShowInvalidRequestNotice();
            DeleteRequest(requestPath);
            return 2;
        }
    }

    Request request{};
    try {
        request = ReadRequestFile(requestPath);
        request.paths = ValidateAndCanonicalize(request.paths);
        if (targetOverride.has_value() && request.action != Action::FitUnder) {
            throw std::runtime_error("target override only valid for Fit Under");
        }
    } catch (const std::exception& error) {
        AppendHistoryLog("invalid", {}, L"", "invalid_request", error.what());
        ShowInvalidRequestNotice();
        DeleteRequest(requestPath);
        return 2;
    }

    RuntimeOutcome outcome = ExecuteValidated(request, targetOverride);
    DeleteRequest(requestPath);
    return outcome.exitCode;
}

} // namespace
} // namespace filedone

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == nullptr) return 2;
    const int result = filedone::Run(argc, argv);
    LocalFree(argv);
    return result;
}
