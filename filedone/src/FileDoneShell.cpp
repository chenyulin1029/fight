#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>
#include <vector>
#include <atomic>
#include <algorithm>
#include <new>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

static HMODULE g_module = nullptr;
static std::atomic<long> g_objects{0};
static std::atomic<long> g_locks{0};

static const CLSID CLSID_FileDone =
{0x72E5C740,0xAB37,0x4FD8,{0x94,0xE8,0x4D,0xE0,0xEC,0xA2,0x92,0xB5}};

static HRESULT DupTaskString(const wchar_t* s, PWSTR* out)
{
    if (!out) return E_POINTER;
    *out = nullptr;
    if (!s) return E_INVALIDARG;
    const size_t n = wcslen(s) + 1;
    auto* p = static_cast<wchar_t*>(CoTaskMemAlloc(n * sizeof(wchar_t)));
    if (!p) return E_OUTOFMEMORY;
    memcpy(p, s, n * sizeof(wchar_t));
    *out = p;
    return S_OK;
}

static std::wstring ModuleDir()
{
    wchar_t buf[32768]{};
    DWORD n = GetModuleFileNameW(g_module, buf, ARRAYSIZE(buf));
    if (!n || n >= ARRAYSIZE(buf)) return L"";
    std::wstring p(buf, n);
    auto pos = p.find_last_of(L"\\/");
    return pos == std::wstring::npos ? L"" : p.substr(0, pos);
}

static std::wstring LocalAppData()
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw)) || !raw) return L"";
    std::wstring s(raw);
    CoTaskMemFree(raw);
    return s;
}

static bool EnsureDir(const std::wstring& p)
{
    if (CreateDirectoryW(p.c_str(), nullptr)) return true;
    return GetLastError() == ERROR_ALREADY_EXISTS;
}

static HRESULT GetPaths(IShellItemArray* items, std::vector<std::wstring>& paths)
{
    if (!items) return E_INVALIDARG;
    DWORD count = 0;
    HRESULT hr = items->GetCount(&count);
    if (FAILED(hr)) return hr;
    for (DWORD i = 0; i < count; ++i)
    {
        IShellItem* item = nullptr;
        hr = items->GetItemAt(i, &item);
        if (FAILED(hr) || !item) continue;
        PWSTR raw = nullptr;
        hr = item->GetDisplayName(SIGDN_FILESYSPATH, &raw);
        item->Release();
        if (FAILED(hr) || !raw) continue;
        DWORD a = GetFileAttributesW(raw);
        if (a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY))
            paths.emplace_back(raw);
        CoTaskMemFree(raw);
    }
    return S_OK;
}

static std::wstring Extension(std::wstring p)
{
    auto slash = p.find_last_of(L"\\/");
    auto dot = p.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return L"";
    std::wstring e = p.substr(dot);
    for (auto& c : e) c = (wchar_t)towlower(c);
    return e;
}

static bool In(const std::wstring& e, const wchar_t* const* xs, size_t n)
{
    for (size_t i=0;i<n;++i) if (e == xs[i]) return true;
    return false;
}

static bool IsImage(const std::wstring& p)
{
    static const wchar_t* xs[] = {L".jpg",L".jpeg",L".png",L".gif",L".webp",L".avif",L".heic",L".heif",L".tif",L".tiff",L".bmp"};
    auto e = Extension(p); return In(e, xs, ARRAYSIZE(xs));
}
static bool IsVideo(const std::wstring& p)
{
    static const wchar_t* xs[] = {L".mp4",L".mov",L".mkv",L".webm",L".avi",L".wmv",L".m4v"};
    auto e = Extension(p); return In(e, xs, ARRAYSIZE(xs));
}
static bool IsAudio(const std::wstring& p)
{
    static const wchar_t* xs[] = {L".mp3",L".flac",L".wav",L".ogg",L".opus",L".m4a",L".aac",L".wma"};
    auto e = Extension(p); return In(e, xs, ARRAYSIZE(xs));
}
static bool IsMedia(const std::wstring& p) { return IsImage(p) || IsVideo(p) || IsAudio(p); }

enum class Action { Compatible, Smaller, FitUnder, SafeShare, MakePdf };

static const wchar_t* ActionToken(Action a)
{
    switch(a) {
        case Action::Compatible: return L"compatible";
        case Action::Smaller: return L"smaller";
        case Action::FitUnder: return L"fitunder";
        case Action::SafeShare: return L"safeshare";
        case Action::MakePdf: return L"makepdf";
    }
    return L"";
}

static HRESULT Submit(Action a, const std::vector<std::wstring>& paths)
{
    if (paths.empty()) return E_INVALIDARG;
    std::wstring root = LocalAppData();
    if (root.empty()) return E_FAIL;
    root += L"\\FileDone"; EnsureDir(root);
    std::wstring reqDir = root + L"\\requests"; EnsureDir(reqDir);
    GUID g{}; if (FAILED(CoCreateGuid(&g))) return E_FAIL;
    wchar_t gb[64]{}; StringFromGUID2(g, gb, ARRAYSIZE(gb));
    std::wstring name(gb); name.erase(std::remove(name.begin(), name.end(), L'{'), name.end()); name.erase(std::remove(name.begin(), name.end(), L'}'), name.end());
    std::wstring req = reqDir + L"\\" + name + L".fdreq";
    HANDLE h = CreateFileW(req.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY, nullptr);
    if (h == INVALID_HANDLE_VALUE) return HRESULT_FROM_WIN32(GetLastError());
    std::wstring text; text.push_back((wchar_t)0xFEFF); text += ActionToken(a); text += L"\r\n";
    for (auto& p : paths) { text += p; text += L"\r\n"; }
    DWORD wrote=0, bytes=(DWORD)(text.size()*sizeof(wchar_t));
    BOOL ok=WriteFile(h,text.data(),bytes,&wrote,nullptr); CloseHandle(h);
    if (!ok || wrote != bytes) { DeleteFileW(req.c_str()); return E_FAIL; }

    std::wstring bridge = ModuleDir() + L"\\FileDoneBridge.exe";
    if (GetFileAttributesW(bridge.c_str()) == INVALID_FILE_ATTRIBUTES) { DeleteFileW(req.c_str()); return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND); }
    std::wstring cmd = L"\"" + bridge + L"\" \"" + req + L"\"";
    std::vector<wchar_t> mutableCmd(cmd.begin(), cmd.end()); mutableCmd.push_back(0);
    STARTUPINFOW si{}; si.cb=sizeof(si); PROCESS_INFORMATION pi{};
    ok=CreateProcessW(bridge.c_str(),mutableCmd.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW|CREATE_UNICODE_ENVIRONMENT,nullptr,nullptr,&si,&pi);
    if (!ok) { DeleteFileW(req.c_str()); return HRESULT_FROM_WIN32(GetLastError()); }
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    return S_OK;
}

class RefCounted {
    std::atomic<ULONG> refs_{1};
protected:
    RefCounted(){ ++g_objects; }
    virtual ~RefCounted(){ --g_objects; }
    ULONG AddRefImpl(){ return ++refs_; }
    ULONG ReleaseImpl(){ ULONG r=--refs_; if(!r) delete this; return r; }
};

class ActionCommand final : public IExplorerCommand, public RefCounted {
    Action action_;
public:
    explicit ActionCommand(Action a):action_(a){}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override { if(!ppv)return E_POINTER; *ppv=nullptr; if(riid==IID_IUnknown||riid==IID_IExplorerCommand){*ppv=static_cast<IExplorerCommand*>(this);AddRef();return S_OK;}return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return AddRefImpl(); }
    ULONG STDMETHODCALLTYPE Release() override { return ReleaseImpl(); }
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*, LPWSTR* t) override { const wchar_t* s=L""; switch(action_){case Action::Compatible:s=L"Make Compatible";break;case Action::Smaller:s=L"Make Smaller";break;case Action::FitUnder:s=L"Fit Under...";break;case Action::SafeShare:s=L"Safe to Share";break;case Action::MakePdf:s=L"Make PDF";break;} return DupTaskString(s,t); }
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* p) override { if(!p)return E_POINTER;*p=nullptr;return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* p) override { if(!p)return E_POINTER;*p=nullptr;return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* g) override { if(!g)return E_POINTER; *g=GUID_NULL; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override { if(!state)return E_POINTER; std::vector<std::wstring> ps; GetPaths(items,ps); bool enabled=!ps.empty(); if(action_==Action::MakePdf){for(auto&p:ps) if(!IsImage(p)) enabled=false;} else if(action_==Action::FitUnder){enabled=ps.size()==1&&(IsImage(ps[0])||IsVideo(ps[0]));} else {for(auto&p:ps) if(!IsMedia(p)) enabled=false;} *state=enabled?ECS_ENABLED:ECS_DISABLED; return S_OK; }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray* items, IBindCtx*) override { std::vector<std::wstring> ps; HRESULT hr=GetPaths(items,ps); if(FAILED(hr))return hr; return Submit(action_,ps); }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* f) override { if(!f)return E_POINTER;*f=ECF_DEFAULT;return S_OK; }
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** p) override { if(p)*p=nullptr;return E_NOTIMPL; }
};

class CommandEnum final : public IEnumExplorerCommand, public RefCounted {
    std::vector<IExplorerCommand*> cmds_; ULONG index_=0;
public:
    CommandEnum(){cmds_.push_back(new ActionCommand(Action::Compatible));cmds_.push_back(new ActionCommand(Action::Smaller));cmds_.push_back(new ActionCommand(Action::FitUnder));cmds_.push_back(new ActionCommand(Action::SafeShare));cmds_.push_back(new ActionCommand(Action::MakePdf));}
    ~CommandEnum(){for(auto*p:cmds_)p->Release();}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {if(!ppv)return E_POINTER;*ppv=nullptr;if(riid==IID_IUnknown||riid==IID_IEnumExplorerCommand){*ppv=static_cast<IEnumExplorerCommand*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return AddRefImpl();}
    ULONG STDMETHODCALLTYPE Release() override{return ReleaseImpl();}
    HRESULT STDMETHODCALLTYPE Next(ULONG celt,IExplorerCommand** out,ULONG* fetched) override {if(!out)return E_POINTER;ULONG n=0;while(n<celt&&index_<cmds_.size()){out[n]=cmds_[index_++];out[n]->AddRef();++n;}if(fetched)*fetched=n;return n==celt?S_OK:S_FALSE;}
    HRESULT STDMETHODCALLTYPE Skip(ULONG celt) override {ULONG remain=(ULONG)cmds_.size()-index_;if(celt>remain){index_=(ULONG)cmds_.size();return S_FALSE;}index_+=celt;return S_OK;}
    HRESULT STDMETHODCALLTYPE Reset() override {index_=0;return S_OK;}
    HRESULT STDMETHODCALLTYPE Clone(IEnumExplorerCommand** clone) override {if(!clone)return E_POINTER;*clone=nullptr;auto* e=new(std::nothrow) CommandEnum();if(!e)return E_OUTOFMEMORY;e->index_=index_;*clone=e;return S_OK;}
};

class RootCommand final : public IExplorerCommand, public RefCounted {
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {if(!ppv)return E_POINTER;*ppv=nullptr;if(riid==IID_IUnknown||riid==IID_IExplorerCommand){*ppv=static_cast<IExplorerCommand*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return AddRefImpl();}
    ULONG STDMETHODCALLTYPE Release() override{return ReleaseImpl();}
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*, LPWSTR* t) override{return DupTaskString(L"FileDone",t);}
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* p) override {if(!p)return E_POINTER;*p=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* p) override {if(!p)return E_POINTER;*p=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* g) override {if(!g)return E_POINTER;*g=CLSID_FileDone;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {if(!state)return E_POINTER;std::vector<std::wstring> ps;GetPaths(items,ps);*state=ps.empty()?ECS_DISABLED:ECS_ENABLED;return S_OK;}
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray*, IBindCtx*) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* f) override {if(!f)return E_POINTER;*f=ECF_HASSUBCOMMANDS;return S_OK;}
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** p) override {if(!p)return E_POINTER;*p=new(std::nothrow) CommandEnum();return *p?S_OK:E_OUTOFMEMORY;}
};

class Factory final : public IClassFactory, public RefCounted {
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,void**ppv) override {if(!ppv)return E_POINTER;*ppv=nullptr;if(riid==IID_IUnknown||riid==IID_IClassFactory){*ppv=static_cast<IClassFactory*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return AddRefImpl();}
    ULONG STDMETHODCALLTYPE Release() override{return ReleaseImpl();}
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID riid,void**ppv) override {if(outer)return CLASS_E_NOAGGREGATION;auto* o=new(std::nothrow) RootCommand();if(!o)return E_OUTOFMEMORY;HRESULT hr=o->QueryInterface(riid,ppv);o->Release();return hr;}
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {if(lock)++g_locks;else--g_locks;return S_OK;}
};

extern "C" BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){g_module=h;DisableThreadLibraryCalls(h);}return TRUE;}
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID rclsid,REFIID riid,void**ppv){if(!IsEqualCLSID(rclsid,CLSID_FileDone))return CLASS_E_CLASSNOTAVAILABLE;auto*f=new(std::nothrow) Factory();if(!f)return E_OUTOFMEMORY;HRESULT hr=f->QueryInterface(riid,ppv);f->Release();return hr;}
extern "C" HRESULT __stdcall DllCanUnloadNow(){return(g_objects.load()==0&&g_locks.load()==0)?S_OK:S_FALSE;}
