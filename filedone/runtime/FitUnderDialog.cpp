#include "FitUnderDialog.h"

#include <cerrno>
#include <cmath>
#include <cwchar>
#include <cwctype>
#include <string>

namespace filedone {
namespace {

constexpr wchar_t kWindowClass[] = L"FileDoneFitUnderDialog";
constexpr int kEditId = 1001;

struct DialogState {
    HWND owner = nullptr;
    HWND edit = nullptr;
    bool done = false;
    std::optional<double> result;
};

std::wstring Trim(const std::wstring& text) {
    size_t first = 0;
    while (first < text.size() && std::iswspace(text[first]) != 0) ++first;

    size_t last = text.size();
    while (last > first && std::iswspace(text[last - 1]) != 0) --last;
    return text.substr(first, last - first);
}

size_t CountOccurrences(const std::wstring& text, const std::wstring& token) {
    if (token.empty()) return 0;
    size_t count = 0;
    size_t pos = 0;
    while ((pos = text.find(token, pos)) != std::wstring::npos) {
        ++count;
        pos += token.size();
    }
    return count;
}

std::wstring UserDecimalSeparator() {
    wchar_t buffer[16]{};
    const int length = GetLocaleInfoEx(
        LOCALE_NAME_USER_DEFAULT,
        LOCALE_SDECIMAL,
        buffer,
        static_cast<int>(std::size(buffer)));
    if (length <= 1) return L".";
    return std::wstring(buffer, static_cast<size_t>(length - 1));
}

void Finish(DialogState* state, HWND window, std::optional<double> result) {
    if (state == nullptr || state->done) return;
    state->result = result;
    state->done = true;
    DestroyWindow(window);
}

void Submit(DialogState* state, HWND window) {
    if (state == nullptr || state->edit == nullptr) return;

    const int length = GetWindowTextLengthW(state->edit);
    std::wstring text(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(state->edit, text.data(), length + 1);
    text.resize(static_cast<size_t>(length));

    const auto parsed = ParseTargetMbText(text, UserDecimalSeparator());
    if (!parsed.has_value()) {
        MessageBoxW(
            window,
            L"Enter a size greater than 0 MB.",
            L"FileDone",
            MB_OK | MB_ICONINFORMATION);
        SetFocus(state->edit);
        SendMessageW(state->edit, EM_SETSEL, 0, -1);
        return;
    }

    Finish(state, window, parsed);
}

LRESULT CALLBACK DialogProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    auto* state = reinterpret_cast<DialogState*>(GetWindowLongPtrW(window, GWLP_USERDATA));

    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
        state = static_cast<DialogState*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }

    switch (message) {
    case WM_CREATE: {
        if (state == nullptr) return -1;
        CreateWindowExW(
            0, L"STATIC", L"Target size in MB",
            WS_CHILD | WS_VISIBLE,
            20, 18, 250, 22,
            window, nullptr, GetModuleHandleW(nullptr), nullptr);

        state->edit = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"10",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
            20, 45, 250, 25,
            window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEditId)),
            GetModuleHandleW(nullptr), nullptr);

        CreateWindowExW(
            0, L"BUTTON", L"OK",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
            104, 88, 80, 28,
            window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDOK)),
            GetModuleHandleW(nullptr), nullptr);

        CreateWindowExW(
            0, L"BUTTON", L"Cancel",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
            190, 88, 80, 28,
            window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDCANCEL)),
            GetModuleHandleW(nullptr), nullptr);

        if (state->edit == nullptr) return -1;
        SetFocus(state->edit);
        SendMessageW(state->edit, EM_SETSEL, 0, -1);
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK) {
            Submit(state, window);
            return 0;
        }
        if (LOWORD(wParam) == IDCANCEL) {
            Finish(state, window, std::nullopt);
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if (wParam == VK_RETURN) {
            Submit(state, window);
            return 0;
        }
        if (wParam == VK_ESCAPE) {
            Finish(state, window, std::nullopt);
            return 0;
        }
        break;
    case WM_CLOSE:
        Finish(state, window, std::nullopt);
        return 0;
    default:
        break;
    }

    return DefWindowProcW(window, message, wParam, lParam);
}

ATOM EnsureWindowClass() {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DialogProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(static_cast<INT_PTR>(COLOR_WINDOW + 1));
    wc.lpszClassName = kWindowClass;

    const ATOM atom = RegisterClassExW(&wc);
    if (atom != 0) return atom;
    if (GetLastError() == ERROR_CLASS_ALREADY_EXISTS) return 1;
    return 0;
}

void CenterWindow(HWND window, HWND owner) {
    RECT target{};
    bool haveTarget = false;
    if (owner != nullptr && IsWindow(owner) != FALSE) {
        haveTarget = GetWindowRect(owner, &target) != FALSE;
    }
    if (!haveTarget) {
        haveTarget = SystemParametersInfoW(SPI_GETWORKAREA, 0, &target, 0) != FALSE;
    }
    if (!haveTarget) return;

    RECT rect{};
    if (GetWindowRect(window, &rect) == FALSE) return;
    const int width = rect.right - rect.left;
    const int height = rect.bottom - rect.top;
    const int x = target.left + ((target.right - target.left) - width) / 2;
    const int y = target.top + ((target.bottom - target.top) - height) / 2;
    SetWindowPos(window, nullptr, x, y, 0, 0, SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

} // namespace

std::optional<double> ParseTargetMbText(
    const std::wstring& text,
    const std::wstring& localDecimalSeparator) {

    std::wstring normalized = Trim(text);
    if (normalized.empty()) return std::nullopt;

    const std::wstring local = localDecimalSeparator.empty() ? L"." : localDecimalSeparator;
    const size_t dotCount = CountOccurrences(normalized, L".");

    if (local != L".") {
        const size_t localCount = CountOccurrences(normalized, local);
        if (dotCount > 1 || localCount > 1 || (dotCount > 0 && localCount > 0)) {
            return std::nullopt;
        }
        if (localCount == 1) {
            const size_t pos = normalized.find(local);
            normalized.replace(pos, local.size(), L".");
        }
    } else if (dotCount > 1) {
        return std::nullopt;
    }

    errno = 0;
    wchar_t* end = nullptr;
    const double value = std::wcstod(normalized.c_str(), &end);
    if (end == normalized.c_str() || end == nullptr || *end != L'\0') return std::nullopt;
    if (errno == ERANGE || !std::isfinite(value) || value <= 0.0) return std::nullopt;
    return value;
}

std::optional<double> PromptTargetMb(HWND owner) {
    if (EnsureWindowClass() == 0) return std::nullopt;

    DialogState state{};
    state.owner = owner;

    HWND window = CreateWindowExW(
        WS_EX_DLGMODALFRAME,
        kWindowClass,
        L"FileDone",
        WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT, CW_USEDEFAULT, 310, 165,
        owner,
        nullptr,
        GetModuleHandleW(nullptr),
        &state);
    if (window == nullptr) return std::nullopt;

    CenterWindow(window, owner);
    if (owner != nullptr && IsWindow(owner) != FALSE) EnableWindow(owner, FALSE);
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);

    MSG message{};
    while (!state.done) {
        const BOOL result = GetMessageW(&message, nullptr, 0, 0);
        if (result <= 0) {
            state.done = true;
            state.result.reset();
            break;
        }

        if (message.message == WM_KEYDOWN && message.hwnd == state.edit) {
            if (message.wParam == VK_RETURN) {
                Submit(&state, window);
                continue;
            }
            if (message.wParam == VK_ESCAPE) {
                Finish(&state, window, std::nullopt);
                continue;
            }
        }

        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    if (IsWindow(window) != FALSE) DestroyWindow(window);
    if (owner != nullptr && IsWindow(owner) != FALSE) {
        EnableWindow(owner, TRUE);
        SetForegroundWindow(owner);
    }
    return state.result;
}

} // namespace filedone
