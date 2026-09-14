#include "ActionMutex.h"
#include "PathPolicy.h"

#include <bcrypt.h>
#include <array>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <utility>

#pragma comment(lib, "bcrypt.lib")

namespace filedone {
namespace {

std::wstring ActionToken(Action action) {
    switch (action) {
        case Action::Compatible: return L"compatible";
        case Action::Smaller: return L"smaller";
        case Action::FitUnder: return L"fitunder";
        case Action::SafeShare: return L"safeshare";
        case Action::MakePdf: return L"makepdf";
    }
    throw std::runtime_error("unknown action");
}

std::wstring LowerInvariant(const std::wstring& input) {
    if (input.empty()) return {};
    int needed = LCMapStringEx(
        LOCALE_NAME_INVARIANT,
        LCMAP_LOWERCASE,
        input.data(),
        static_cast<int>(input.size()),
        nullptr,
        0,
        nullptr,
        nullptr,
        0);
    if (needed <= 0) throw std::runtime_error("LCMapStringEx size failed");

    std::wstring output(static_cast<size_t>(needed), L'\0');
    int written = LCMapStringEx(
        LOCALE_NAME_INVARIANT,
        LCMAP_LOWERCASE,
        input.data(),
        static_cast<int>(input.size()),
        output.data(),
        needed,
        nullptr,
        nullptr,
        0);
    if (written != needed) throw std::runtime_error("LCMapStringEx failed");
    return output;
}

std::string Utf8(const std::wstring& input) {
    if (input.empty()) return {};
    int needed = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (needed <= 0) throw std::runtime_error("WideCharToMultiByte size failed");

    std::string output(static_cast<size_t>(needed), '\0');
    int written = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        input.data(),
        static_cast<int>(input.size()),
        output.data(),
        needed,
        nullptr,
        nullptr);
    if (written != needed) throw std::runtime_error("WideCharToMultiByte failed");
    return output;
}

std::array<unsigned char, 32> Sha256(const std::string& bytes) {
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD objectLength = 0;
    DWORD cbData = 0;

    NTSTATUS status = BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (status < 0) throw std::runtime_error("BCryptOpenAlgorithmProvider failed");

    status = BCryptGetProperty(
        alg,
        BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&objectLength),
        sizeof(objectLength),
        &cbData,
        0);
    if (status < 0) {
        BCryptCloseAlgorithmProvider(alg, 0);
        throw std::runtime_error("BCryptGetProperty failed");
    }

    std::vector<unsigned char> object(objectLength);
    status = BCryptCreateHash(
        alg,
        &hash,
        object.data(),
        static_cast<ULONG>(object.size()),
        nullptr,
        0,
        0);
    if (status < 0) {
        BCryptCloseAlgorithmProvider(alg, 0);
        throw std::runtime_error("BCryptCreateHash failed");
    }

    status = BCryptHashData(
        hash,
        reinterpret_cast<PUCHAR>(const_cast<char*>(bytes.data())),
        static_cast<ULONG>(bytes.size()),
        0);
    if (status < 0) {
        BCryptDestroyHash(hash);
        BCryptCloseAlgorithmProvider(alg, 0);
        throw std::runtime_error("BCryptHashData failed");
    }

    std::array<unsigned char, 32> digest{};
    status = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0);
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    if (status < 0) throw std::runtime_error("BCryptFinishHash failed");
    return digest;
}

std::wstring HexUpper(const std::array<unsigned char, 32>& bytes) {
    std::wostringstream out;
    out << std::uppercase << std::hex << std::setfill(L'0');
    for (unsigned char b : bytes) out << std::setw(2) << static_cast<unsigned int>(b);
    return out.str();
}

} // namespace

std::wstring BuildActionMutexName(
    Action action,
    const std::vector<std::wstring>& canonicalPaths) {

    std::wstring material = LowerInvariant(ActionToken(action));
    for (const auto& path : canonicalPaths) {
        material += L"\n";
        material += LowerInvariant(CanonicalPath(path));
    }
    const auto digest = Sha256(Utf8(material));
    return L"Local\\FileDone_Action_" + HexUpper(digest);
}

ActionMutex::ActionMutex(
    Action action,
    const std::vector<std::wstring>& canonicalPaths) {

    const auto name = BuildActionMutexName(action, canonicalPaths);
    handle_ = CreateMutexW(nullptr, FALSE, name.c_str());
    if (!handle_) throw std::runtime_error("CreateMutexW failed");

    const DWORD wait = WaitForSingleObject(handle_, 30u * 60u * 1000u);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
        acquired_ = true;
        return;
    }

    CloseHandle(handle_);
    handle_ = nullptr;
    if (wait == WAIT_TIMEOUT) throw std::runtime_error("action mutex timeout");
    throw std::runtime_error("action mutex wait failed");
}

ActionMutex::~ActionMutex() {
    if (handle_) {
        if (acquired_) ReleaseMutex(handle_);
        CloseHandle(handle_);
    }
}

ActionMutex::ActionMutex(ActionMutex&& other) noexcept
    : handle_(std::exchange(other.handle_, nullptr)),
      acquired_(std::exchange(other.acquired_, false)) {}

ActionMutex& ActionMutex::operator=(ActionMutex&& other) noexcept {
    if (this == &other) return *this;
    if (handle_) {
        if (acquired_) ReleaseMutex(handle_);
        CloseHandle(handle_);
    }
    handle_ = std::exchange(other.handle_, nullptr);
    acquired_ = std::exchange(other.acquired_, false);
    return *this;
}

} // namespace filedone
