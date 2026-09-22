#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shobjidl.h>
#include <shlobj_core.h>
#include <iostream>
#include <string>
#include <vector>

static const CLSID CLSID_FileDone =
{0x72E5C740,0xAB37,0x4FD8,{0x94,0xE8,0x4D,0xE0,0xEC,0xA2,0x92,0xB5}};

static bool Eq(const wchar_t* a, const wchar_t* b) {
    return a && b && wcscmp(a, b) == 0;
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 2 || argv[1] == nullptr || *argv[1] == L'\0') {
        std::wcerr << L"fixture path required\n";
        return 2;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) {
        std::wcerr << L"CoInitializeEx failed hr=0x" << std::hex << hr << L"\n";
        return 3;
    }

    IExplorerCommand* root = nullptr;
    hr = CoCreateInstance(CLSID_FileDone, nullptr, CLSCTX_ALL, IID_PPV_ARGS(&root));
    if (FAILED(hr) || root == nullptr) {
        std::wcerr << L"CoCreateInstance failed hr=0x" << std::hex << hr << L"\n";
        CoUninitialize();
        return 4;
    }

    int result = 1;
    do {
        PWSTR rootTitle = nullptr;
        hr = root->GetTitle(nullptr, &rootTitle);
        if (FAILED(hr) || !Eq(rootTitle, L"FileDone")) {
            std::wcerr << L"root title invalid hr=0x" << std::hex << hr << L"\n";
            if (rootTitle) CoTaskMemFree(rootTitle);
            break;
        }
        CoTaskMemFree(rootTitle);

        GUID canonical{};
        hr = root->GetCanonicalName(&canonical);
        if (FAILED(hr) || !IsEqualGUID(canonical, CLSID_FileDone)) {
            std::wcerr << L"canonical CLSID mismatch hr=0x" << std::hex << hr << L"\n";
            break;
        }

        EXPCMDFLAGS flags = ECF_DEFAULT;
        hr = root->GetFlags(&flags);
        if (FAILED(hr) || (flags & ECF_HASSUBCOMMANDS) == 0) {
            std::wcerr << L"root flags missing ECF_HASSUBCOMMANDS hr=0x" << std::hex << hr << L"\n";
            break;
        }

        IShellItem* item = nullptr;
        hr = SHCreateItemFromParsingName(argv[1], nullptr, IID_PPV_ARGS(&item));
        if (FAILED(hr) || item == nullptr) {
            std::wcerr << L"SHCreateItemFromParsingName failed hr=0x" << std::hex << hr << L"\n";
            break;
        }

        IShellItemArray* items = nullptr;
        hr = SHCreateShellItemArrayFromShellItem(item, IID_PPV_ARGS(&items));
        item->Release();
        if (FAILED(hr) || items == nullptr) {
            std::wcerr << L"SHCreateShellItemArrayFromShellItem failed hr=0x" << std::hex << hr << L"\n";
            break;
        }

        IEnumExplorerCommand* e = nullptr;
        hr = root->EnumSubCommands(&e);
        if (FAILED(hr) || e == nullptr) {
            std::wcerr << L"EnumSubCommands failed hr=0x" << std::hex << hr << L"\n";
            items->Release();
            break;
        }

        const wchar_t* expected[] = {
            L"Make Compatible",
            L"Make Smaller",
            L"Fit Under...",
            L"Safe to Share",
            L"Make PDF"
        };
        std::vector<std::wstring> titles;
        bool invokedCompatible = false;

        for (;;) {
            IExplorerCommand* command = nullptr;
            ULONG fetched = 0;
            hr = e->Next(1, &command, &fetched);
            if (hr == S_FALSE || fetched == 0) break;
            if (FAILED(hr) || command == nullptr) {
                std::wcerr << L"subcommand Next failed hr=0x" << std::hex << hr << L"\n";
                break;
            }

            PWSTR title = nullptr;
            HRESULT titleHr = command->GetTitle(items, &title);
            if (FAILED(titleHr) || title == nullptr) {
                std::wcerr << L"subcommand title failed hr=0x" << std::hex << titleHr << L"\n";
                command->Release();
                hr = titleHr;
                break;
            }

            titles.emplace_back(title);
            if (wcscmp(title, L"Make Compatible") == 0) {
                EXPCMDSTATE state = ECS_HIDDEN;
                HRESULT stateHr = command->GetState(items, FALSE, &state);
                if (FAILED(stateHr) || state != ECS_ENABLED) {
                    std::wcerr << L"Make Compatible not enabled hr=0x" << std::hex << stateHr
                               << L" state=" << static_cast<unsigned>(state) << L"\n";
                    CoTaskMemFree(title);
                    command->Release();
                    hr = FAILED(stateHr) ? stateHr : E_FAIL;
                    break;
                }

                HRESULT invokeHr = command->Invoke(items, nullptr);
                if (FAILED(invokeHr)) {
                    std::wcerr << L"Make Compatible Invoke failed hr=0x" << std::hex << invokeHr << L"\n";
                    CoTaskMemFree(title);
                    command->Release();
                    hr = invokeHr;
                    break;
                }
                invokedCompatible = true;
            }

            CoTaskMemFree(title);
            command->Release();
            hr = S_OK;
        }

        e->Release();
        items->Release();

        if (FAILED(hr)) break;
        if (titles.size() != 5) {
            std::wcerr << L"unexpected subcommand count=" << titles.size() << L"\n";
            break;
        }
        for (size_t i = 0; i < titles.size(); ++i) {
            if (titles[i] != expected[i]) {
                std::wcerr << L"subcommand mismatch index=" << i << L" got=" << titles[i] << L"\n";
                hr = E_FAIL;
                break;
            }
        }
        if (FAILED(hr)) break;
        if (!invokedCompatible) {
            std::wcerr << L"Make Compatible was not invoked\n";
            break;
        }

        std::wcout << L"FILEDONE_PACKAGED_COM_ACTIVATION_PASS\n";
        std::wcout << L"FILEDONE_PACKAGED_EXPLORERCOMMAND_ENUM_PASS COUNT=5\n";
        std::wcout << L"FILEDONE_PACKAGED_SHELL_INVOKE_SUBMITTED action=Make Compatible\n";
        result = 0;
    } while (false);

    root->Release();
    CoUninitialize();
    return result;
}
