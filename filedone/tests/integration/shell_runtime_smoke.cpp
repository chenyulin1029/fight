#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <chrono>
#include <filesystem>
#include <set>
#include <string>
#include <thread>

namespace {

const CLSID kFileDoneClsid =
{0x72E5C740,0xAB37,0x4FD8,{0x94,0xE8,0x4D,0xE0,0xEC,0xA2,0x92,0xB5}};

using DllGetClassObjectFn = HRESULT (__stdcall*)(REFCLSID, REFIID, void**);
using DllCanUnloadNowFn = HRESULT (__stdcall*)();

std::set<std::wstring> RequestFiles() {
    std::set<std::wstring> result;
    PWSTR local = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local)) || local == nullptr) {
        return result;
    }
    const std::filesystem::path dir = std::filesystem::path(local) / L"FileDone" / L"requests";
    CoTaskMemFree(local);

    std::error_code ec;
    if (!std::filesystem::is_directory(dir, ec) || ec) return result;
    for (std::filesystem::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        if (it->is_regular_file(ec) && !ec && it->path().extension() == L".fdreq") {
            result.insert(it->path().filename().wstring());
        }
    }
    return result;
}

bool NoNewRequestFiles(const std::set<std::wstring>& before) {
    const auto after = RequestFiles();
    for (const auto& name : after) {
        if (before.find(name) == before.end()) return false;
    }
    return true;
}

bool WaitForOutputAndCleanup(
    const std::wstring& output,
    const std::set<std::wstring>& requestsBefore) {

    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(45);
    while (std::chrono::steady_clock::now() < deadline) {
        std::error_code ec;
        const bool outputReady = std::filesystem::is_regular_file(output, ec) && !ec &&
            std::filesystem::file_size(output, ec) > 0 && !ec;
        if (outputReady && NoNewRequestFiles(requestsBefore)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    return false;
}

int Fail(int code) {
    return code;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 4) return Fail(2);
    const std::wstring dllPath = argv[1];
    const std::wstring inputPath = argv[2];
    const std::wstring expectedOutput = argv[3];

    const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(init)) return Fail(3);

    HMODULE module = LoadLibraryW(dllPath.c_str());
    if (module == nullptr) {
        CoUninitialize();
        return Fail(4);
    }

    auto getClassObject = reinterpret_cast<DllGetClassObjectFn>(
        GetProcAddress(module, "DllGetClassObject"));
    auto canUnloadNow = reinterpret_cast<DllCanUnloadNowFn>(
        GetProcAddress(module, "DllCanUnloadNow"));
    if (getClassObject == nullptr || canUnloadNow == nullptr) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(5);
    }

    IClassFactory* factory = nullptr;
    HRESULT hr = getClassObject(kFileDoneClsid, IID_IClassFactory, reinterpret_cast<void**>(&factory));
    if (FAILED(hr) || factory == nullptr) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(6);
    }

    IExplorerCommand* root = nullptr;
    hr = factory->CreateInstance(nullptr, IID_IExplorerCommand, reinterpret_cast<void**>(&root));
    factory->Release();
    if (FAILED(hr) || root == nullptr) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(7);
    }

    IEnumExplorerCommand* commands = nullptr;
    hr = root->EnumSubCommands(&commands);
    root->Release();
    if (FAILED(hr) || commands == nullptr) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(8);
    }

    IExplorerCommand* smaller = nullptr;
    for (;;) {
        IExplorerCommand* command = nullptr;
        ULONG fetched = 0;
        hr = commands->Next(1, &command, &fetched);
        if (hr != S_OK || fetched != 1 || command == nullptr) break;

        PWSTR title = nullptr;
        const HRESULT titleHr = command->GetTitle(nullptr, &title);
        const bool match = SUCCEEDED(titleHr) && title != nullptr &&
            std::wstring(title) == L"Make Smaller";
        if (title != nullptr) CoTaskMemFree(title);
        if (match) {
            smaller = command;
            break;
        }
        command->Release();
    }
    commands->Release();
    if (smaller == nullptr) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(9);
    }

    IShellItem* item = nullptr;
    hr = SHCreateItemFromParsingName(inputPath.c_str(), nullptr, IID_PPV_ARGS(&item));
    if (FAILED(hr) || item == nullptr) {
        smaller->Release();
        FreeLibrary(module);
        CoUninitialize();
        return Fail(10);
    }

    IShellItemArray* array = nullptr;
    hr = SHCreateShellItemArrayFromShellItem(item, IID_PPV_ARGS(&array));
    item->Release();
    if (FAILED(hr) || array == nullptr) {
        smaller->Release();
        FreeLibrary(module);
        CoUninitialize();
        return Fail(11);
    }

    EXPCMDSTATE state = ECS_DISABLED;
    hr = smaller->GetState(array, FALSE, &state);
    if (FAILED(hr) || state != ECS_ENABLED) {
        array->Release();
        smaller->Release();
        FreeLibrary(module);
        CoUninitialize();
        return Fail(12);
    }

    const auto requestsBefore = RequestFiles();
    hr = smaller->Invoke(array, nullptr);
    array->Release();
    smaller->Release();
    if (FAILED(hr)) {
        FreeLibrary(module);
        CoUninitialize();
        return Fail(13);
    }

    const bool completed = WaitForOutputAndCleanup(expectedOutput, requestsBefore);
    const HRESULT unloadState = canUnloadNow();
    FreeLibrary(module);
    CoUninitialize();

    if (!completed) return Fail(14);
    if (unloadState != S_OK) return Fail(15);
    return 0;
}
