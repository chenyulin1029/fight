# FileDone P1.8A Native Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shipping PowerShell execution path with a native C++ `FileDoneRuntime.exe` while preserving the proven P1.5.2 product behavior and reaching `NATIVE_RUNTIME_PASS` plus `ORACLE_PARITY_PASS`.

**Architecture:** Keep the current Explorer `IExplorerCommand` request contract initially, but make a new native runtime parse the UTF-16 request file, own output naming/concurrency/error handling, and invoke fixed FFmpeg/FFprobe/ImageMagick binaries directly with `CreateProcessW`. The frozen P1.5.2 PowerShell Core is retained only under `filedone/tests/oracle/` as a test oracle and is excluded from shipping packages.

**Tech Stack:** C++17 / Win32, MSVC x64, `std::filesystem`, Windows named mutexes, BCrypt SHA-256, `CreateProcessW`, FFmpeg/FFprobe CLI, ImageMagick CLI, PowerShell only for CI/test harnesses.

**Spec:** `docs/superpowers/specs/2026-09-14-filedone-p1-8-store-release-design.md`

## Global Constraints

- Microsoft Store-first, paid one-time purchase, no trial.
- Windows 11 x64 only.
- Final shipping runtime must not launch PowerShell.
- Original source files remain untouched by default.
- Five actions remain: `compatible`, `smaller`, `fitunder`, `safeshare`, `makepdf`.
- Frozen legacy behavior authority SHA-256 is `6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD`.
- HEIC/HEIF Safe to Share must produce JPG.
- Same action + same canonical input set must serialize across the unique-output-name decision and conversion; different inputs/actions may proceed concurrently.
- Explorer multi-selection order must be preserved for Make PDF.
- Consumer-facing messages must not expose PowerShell, COM, registry, compiler, package, internal gate, or diagnostic-path terminology.
- A failed native-runtime candidate must not alter or replace the current Cross-PC Win32 rollback authority.

---

## File Structure

Create these focused runtime units:

- `filedone/runtime/RuntimeTypes.h` — action/result/request types shared by runtime modules.
- `filedone/runtime/RequestFile.h/.cpp` — parse and validate the existing UTF-16LE `.fdreq` contract.
- `filedone/runtime/PathPolicy.h/.cpp` — extension classification, canonical paths, unique output naming, source-preservation checks.
- `filedone/runtime/ActionMutex.h/.cpp` — deterministic SHA-256 named mutex matching P1.5.2 serialization semantics.
- `filedone/runtime/ProcessRunner.h/.cpp` — direct child-process execution with stdout/stderr capture and no shell.
- `filedone/runtime/Toolchain.h/.cpp` — package-relative tool discovery and version probing.
- `filedone/runtime/MediaProbe.h/.cpp` — ImageMagick opacity/dimension probes and FFprobe video/audio metadata probes.
- `filedone/runtime/ActionEngine.h/.cpp` — the five behavior-preserving action implementations.
- `filedone/runtime/FitUnderDialog.h/.cpp` — native Win32 numeric input dialog for target MB.
- `filedone/runtime/UserNotice.h/.cpp` — consumer-safe success/warning/error UI.
- `filedone/runtime/HistoryLog.h/.cpp` — private local support/history log.
- `filedone/runtime/FileDoneRuntime.cpp` — process entry point, request dispatch, mutex lifetime, exit codes.
- `filedone/tests/TestHarness.h` — tiny assertion runner for C++ unit tests.
- `filedone/tests/runtime_unit_tests.cpp` — parser/naming/mutex/tool argument unit tests.
- `filedone/tests/integration/Run-Round1.ps1` — native-runtime Round 1.2 regression.
- `filedone/tests/integration/Run-Round2.ps1` — native-runtime Round 2 regression.
- `filedone/tests/integration/Run-OracleParity.ps1` — semantic comparison between frozen P1.5.2 and native runtime.
- `filedone/tests/oracle/FileDoneCore.P1.5.2.ps1` — exact frozen test oracle only.
- `filedone/tests/oracle/authority.sha256` — exact required oracle hash.
- `filedone/scripts/build-runtime.ps1` — local/CI MSVC build script.
- `.github/workflows/filedone-p1-8a-runtime.yml` — runtime build/unit/regression/parity CI.

### Task 1: Freeze the legacy oracle and create the native test/build skeleton

**Files:**
- Create: `filedone/tests/oracle/FileDoneCore.P1.5.2.ps1`
- Create: `filedone/tests/oracle/authority.sha256`
- Create: `filedone/tests/TestHarness.h`
- Create: `filedone/tests/runtime_unit_tests.cpp`
- Create: `filedone/scripts/build-runtime.ps1`

**Interfaces:**
- Consumes: frozen P1.5.2 core bytes with SHA-256 `6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD`.
- Produces: `filedone/out/FileDoneRuntime.exe`, `filedone/out/runtime_unit_tests.exe`, and a build that hard-fails if oracle bytes drift.

- [ ] **Step 1: Add the exact frozen oracle and hash guard**

`authority.sha256` must contain exactly:

```text
6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD  FileDoneCore.P1.5.2.ps1
```

The build script must verify it before running parity tests:

```powershell
$expected='6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD'
$actual=(Get-FileHash filedone/tests/oracle/FileDoneCore.P1.5.2.ps1 -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual -ne $expected){ throw "P1.5.2 oracle drift: $actual" }
```

- [ ] **Step 2: Write a failing test harness smoke test**

`runtime_unit_tests.cpp` starts with one deliberate unresolved call to `filedone::ParseActionToken`:

```cpp
#include "TestHarness.h"
#include "../runtime/RuntimeTypes.h"
int main() {
    TEST_EQ(filedone::ParseActionToken(L"compatible"), filedone::Action::Compatible);
    return test::Finish();
}
```

- [ ] **Step 3: Run the build and verify expected failure**

Run:

```powershell
pwsh -File filedone/scripts/build-runtime.ps1
```

Expected: compile/link failure because `RuntimeTypes.h` / `ParseActionToken` do not exist yet.

- [ ] **Step 4: Add the build script compilation contract**

The script must compile with MSVC x64, `/std:c++17 /EHsc /MT /DUNICODE /D_UNICODE`, place outputs under `filedone/out`, and never compile or package the oracle into `FileDoneRuntime.exe`.

- [ ] **Step 5: Commit**

```bash
git add filedone/tests filedone/scripts/build-runtime.ps1
git commit -m "test: freeze P1.5.2 runtime oracle"
```

### Task 2: Define action/request/result types and parse the existing shell request contract

**Files:**
- Create: `filedone/runtime/RuntimeTypes.h`
- Create: `filedone/runtime/RequestFile.h`
- Create: `filedone/runtime/RequestFile.cpp`
- Modify: `filedone/tests/runtime_unit_tests.cpp`

**Interfaces:**
- Produces:
  - `enum class Action { Compatible, Smaller, FitUnder, SafeShare, MakePdf };`
  - `std::optional<Action> ParseActionToken(std::wstring_view);`
  - `struct Request { Action action; std::vector<std::wstring> paths; };`
  - `Request ReadRequestFile(const std::wstring& path);`

- [ ] **Step 1: Write parser tests before implementation**

Cover all five exact tokens, unknown token rejection, UTF-16LE BOM, blank-line rejection, order preservation, and a path containing Chinese/Japanese/emoji.

```cpp
TEST_EQ(*filedone::ParseActionToken(L"makepdf"), filedone::Action::MakePdf);
TEST_FALSE(filedone::ParseActionToken(L"MakePdf").has_value());
TEST_EQ(req.paths[0], L"C:\\測試\\01 中文 空格.jpg");
TEST_EQ(req.paths[1], L"C:\\測試\\02_日本語_😀.png");
```

- [ ] **Step 2: Run tests and verify failure**

Run the build script; expected: missing implementation failures.

- [ ] **Step 3: Implement strict parsing**

Use `CreateFileW` / `ReadFile` or binary `std::ifstream` to require UTF-16LE BOM `0xFEFF`; first logical line is the action token; remaining non-empty lines are paths in original order. Reject an empty selection.

- [ ] **Step 4: Run unit tests**

Expected: parser tests PASS.

- [ ] **Step 5: Commit**

```bash
git add filedone/runtime/RuntimeTypes.h filedone/runtime/RequestFile.* filedone/tests/runtime_unit_tests.cpp
git commit -m "feat: parse native FileDone requests"
```

### Task 3: Implement path classification, unique output naming, and process-safe action mutexes

**Files:**
- Create: `filedone/runtime/PathPolicy.h/.cpp`
- Create: `filedone/runtime/ActionMutex.h/.cpp`
- Modify: `filedone/tests/runtime_unit_tests.cpp`

**Interfaces:**
- Produces:
  - `MediaKind ClassifyMedia(const std::wstring& path);`
  - `std::wstring CanonicalPath(const std::wstring& path);`
  - `std::wstring UniqueOutputPath(const std::wstring& input, std::wstring_view suffix, std::wstring_view extension);`
  - `std::wstring BuildActionMutexName(Action, std::span<const std::wstring> canonicalPaths);`
  - RAII `ActionMutex` that acquires a local Windows mutex for up to 30 minutes and treats `WAIT_ABANDONED` as acquired.

- [ ] **Step 1: Add failing unit tests for extension sets and naming**

Required image set: `.jpg .jpeg .png .gif .webp .avif .heic .heif .tif .tiff .bmp`.
Required video set: `.mp4 .mov .mkv .webm .avi .wmv .m4v`.
Required audio set: `.mp3 .flac .wav .ogg .opus .m4a .aac .wma`.

Test that existing `photo_smaller.jpg` yields `photo_smaller_2.jpg`, then `_3`, never overwrite.

- [ ] **Step 2: Add a deterministic mutex-name test**

The material is:

```text
lower(action-token) + "\n" + lower(full-path-1) + "\n" + ...
```

SHA-256 it with BCrypt and prefix `Local\\FileDone_Action_`.

- [ ] **Step 3: Run tests and verify failure**

Expected: missing path/mutex implementations.

- [ ] **Step 4: Implement and rerun tests**

Use wide Win32 APIs and `std::filesystem`; never convert user paths through the active ANSI code page.

- [ ] **Step 5: Commit**

```bash
git add filedone/runtime/PathPolicy.* filedone/runtime/ActionMutex.* filedone/tests/runtime_unit_tests.cpp
git commit -m "feat: preserve output naming and concurrency contract"
```

### Task 4: Implement direct tool execution and media probing

**Files:**
- Create: `filedone/runtime/ProcessRunner.h/.cpp`
- Create: `filedone/runtime/Toolchain.h/.cpp`
- Create: `filedone/runtime/MediaProbe.h/.cpp`
- Modify: `filedone/tests/runtime_unit_tests.cpp`

**Interfaces:**
- Produces:
  - `ProcessResult RunProcess(const std::wstring& exe, const std::vector<std::wstring>& args);`
  - `Toolchain Toolchain::FromRuntimeDirectory();`
  - `bool ImageIsOpaque(const Toolchain&, const std::wstring&);`
  - `ImageSize GetImageSize(...);`
  - `VideoInfo GetVideoInfo(...);`

- [ ] **Step 1: Write argument-quoting tests**

Cover spaces, quotes, ampersands, parentheses, Unicode, and empty arguments. The command line must round-trip through `CommandLineToArgvW`.

- [ ] **Step 2: Implement `CreateProcessW` runner with redirected stdout/stderr**

Requirements: `CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT`, explicit executable path, inherited anonymous pipe handles only, exit code capture, complete output capture, no `cmd.exe`, no PowerShell.

- [ ] **Step 3: Implement package-relative tool lookup**

Resolve runtime module directory with `GetModuleFileNameW`; require:

```text
tools\ffmpeg.exe
tools\ffprobe.exe
tools\magick.exe
```

For P1.8A local development, allow `FILEDONE_TOOLS_DIR` as a test-only override; production packaging must not depend on it.

- [ ] **Step 4: Implement probes matching P1.5.2 semantics**

Image opacity:

```text
magick identify -quiet -format %[opaque] <path>
```

Image dimensions:

```text
magick identify -quiet -format "%w %h" <path>
```

Video info uses FFprobe `format=duration`, first video `codec_name`, first audio `codec_name`.

- [ ] **Step 5: Run unit/tool smoke tests and commit**

```bash
git add filedone/runtime/ProcessRunner.* filedone/runtime/Toolchain.* filedone/runtime/MediaProbe.* filedone/tests/runtime_unit_tests.cpp
git commit -m "feat: add native media tool runner"
```

### Task 5: Port Make Compatible and Make Smaller exactly

**Files:**
- Create: `filedone/runtime/ActionEngine.h`
- Create: `filedone/runtime/ActionEngine.cpp`
- Create: `filedone/tests/integration/Run-Compatible-Smaller.ps1`

**Interfaces:**
- Produces `ActionResult ExecuteCompatible(...)` and `ActionResult ExecuteSmaller(...)` used by the final dispatcher.

- [ ] **Step 1: Write integration tests for current behavior**

Compatible contracts:

```text
jpg/jpeg/png/gif/mp3 -> NOOP
opaque image -> _compatible.jpg, quality 90
affected transparent image -> _compatible.png
animated WebP -> failure
already H.264/AAC MP4 -> NOOP
other video -> H.264/AAC MP4, CRF 20, preset medium, yuv420p, AAC 160k, faststart
audio -> MP3 192k
```

Smaller contracts:

```text
opaque image -> _smaller.jpg, strip, <=2560x2560, quality 82
transparent image -> _smaller.webp, strip, <=2560x2560, quality 82
video -> MP4 H.264 CRF 28, max width 1920, AAC 128k
audio -> MP3 128k
```

- [ ] **Step 2: Run tests and verify failure**

Expected: action implementation absent.

- [ ] **Step 3: Implement the exact CLI argument vectors**

Do not add new codec heuristics or quality knobs.

- [ ] **Step 4: Assert every PASS output exists and is non-empty**

NOOP is successful with no output path. A nonzero child-process exit is failure and must include private technical detail, not consumer UI detail.

- [ ] **Step 5: Run integration tests and commit**

```bash
git add filedone/runtime/ActionEngine.* filedone/tests/integration/Run-Compatible-Smaller.ps1
git commit -m "feat: port compatible and smaller actions"
```

### Task 6: Port Safe to Share and Make PDF exactly

**Files:**
- Modify: `filedone/runtime/ActionEngine.cpp`
- Create: `filedone/tests/integration/Run-SafeShare-Pdf.ps1`

**Interfaces:**
- Produces `ExecuteSafeShare(...)` and `ExecuteMakePdf(...)`.

- [ ] **Step 1: Write failing Safe to Share tests**

Required behavior:

```text
HEIC/HEIF -> _safe.jpg, auto-orient, strip, JPEG quality 92
other supported image -> same extension, auto-orient, strip
video/audio -> same extension, -map 0 -map_metadata -1 -map_chapters -1 -c copy
```

- [ ] **Step 2: Write failing PDF tests**

Require image-only input, preserve passed order, first selected image owns output base name, suffix `_document.pdf`, ImageMagick arguments end with:

```text
-auto-orient -units PixelsPerInch -density 150 <output>
```

Verify page count equals selected-image count.

- [ ] **Step 3: Implement and rerun tests**

A failed conversion must not leave an artifact that satisfies the success filename pattern.

- [ ] **Step 4: Commit**

```bash
git add filedone/runtime/ActionEngine.cpp filedone/tests/integration/Run-SafeShare-Pdf.ps1
git commit -m "feat: port safe share and pdf actions"
```

### Task 7: Port strict Fit Under plus native target-size input UI

**Files:**
- Modify: `filedone/runtime/ActionEngine.cpp`
- Create: `filedone/runtime/FitUnderDialog.h/.cpp`
- Create: `filedone/tests/integration/Run-FitUnder.ps1`

**Interfaces:**
- Produces `std::optional<double> PromptTargetMb(HWND owner);`
- Produces image/video Fit Under functions that accept an explicit `double targetMb` so automated tests never need UI.

- [ ] **Step 1: Write strict image Fit Under test**

Port the exact search grid:

```text
scales = 1.0,0.9,0.8,0.7,0.6,0.5,0.4
qualities = 88,82,76,70,64,58,52,46,40
minimum dimensions guard = 320x320
opaque output = JPG
transparent output = WebP
```

The PASS assertion is `output_bytes <= target_bytes`.

- [ ] **Step 2: Write strict video Fit Under test**

Port the exact bitrate policy:

```text
total_bps = target_bytes * 8 * 0.965 / duration
audio_bps = 96000
minimum video_bps = 140000
2-pass H.264 medium preset, max width 1920, AAC 96k, yuv420p, faststart
retry at 90% video bitrate once if first result is too large
```

For P1.8 acceptance, tighten the final product assertion to `output_bytes <= target_bytes`; if the legacy 1.01 tolerance produces an oversized result, continue lowering bitrate until within target or return failure. Record this as an intentional bug-fix exception in parity output rather than silently calling it equal.

- [ ] **Step 3: Implement native numeric input dialog**

Create a small programmatic Win32 window with label `Target size in MB`, edit control default `10`, OK/Cancel buttons. Accept invariant or local decimal separator; require finite value `> 0`.

- [ ] **Step 4: Run strict tests and commit**

```bash
git add filedone/runtime/ActionEngine.cpp filedone/runtime/FitUnderDialog.* filedone/tests/integration/Run-FitUnder.ps1
git commit -m "feat: port strict fit-under action"
```

### Task 8: Add runtime entry point, private logging, and consumer notices

**Files:**
- Create: `filedone/runtime/UserNotice.h/.cpp`
- Create: `filedone/runtime/HistoryLog.h/.cpp`
- Create: `filedone/runtime/FileDoneRuntime.cpp`
- Modify: `filedone/scripts/build-runtime.ps1`

**Interfaces:**
- `FileDoneRuntime.exe <request-file>` returns `0` success/NOOP, `1` product operation failure, `2` invalid request, `3` runtime/toolchain unavailable.

- [ ] **Step 1: Write dispatcher integration tests**

Create synthetic `.fdreq` files and verify action selection, Make PDF multi-path preservation, and Fit Under explicit test override `--target-mb <n>` accepted only in test invocation.

- [ ] **Step 2: Implement runtime control flow**

Exact order:

```text
read request -> canonicalize/validate files -> acquire action mutex -> resolve tools -> execute action -> verify output -> log -> consumer notice -> release mutex -> delete request
```

The mutex must cover both unique-name selection and conversion.

- [ ] **Step 3: Implement local support log**

Write UTF-8 JSON Lines under `%LOCALAPPDATA%\FileDone\logs\runtime.jsonl` with timestamp, action, input(s), output, status, internal error summary. Consumer dialogs must not show the log path.

- [ ] **Step 4: Verify no PowerShell launch exists in runtime sources**

Run:

```powershell
Select-String -Path filedone/runtime/* -Pattern 'powershell|pwsh|cmd.exe' -SimpleMatch
```

Expected: no shipping runtime hit.

- [ ] **Step 5: Commit**

```bash
git add filedone/runtime filedone/scripts/build-runtime.ps1 filedone/tests
git commit -m "feat: add native FileDone runtime dispatcher"
```

### Task 9: Switch the shell handoff from Bridge/PowerShell to `FileDoneRuntime.exe`

**Files:**
- Modify: `filedone/src/FileDoneShell.cpp`
- Retain temporarily but stop building: `filedone/src/FileDoneBridge.cpp`
- Modify: `filedone/scripts/build-runtime.ps1`
- Create: `filedone/tests/integration/Run-ShellRuntime-Smoke.ps1`

**Interfaces:**
- Shell request file format remains unchanged.
- `Submit()` launches `FileDoneRuntime.exe` from the DLL module directory.

- [ ] **Step 1: Write a source-level failing assertion**

The smoke test must fail while `FileDoneShell.cpp` still contains `FileDoneBridge.exe`.

- [ ] **Step 2: Modify only the executable handoff**

Replace the module-relative target with `FileDoneRuntime.exe`; keep request creation and real `IShellItemArray` extraction unchanged.

- [ ] **Step 3: Build shell + runtime and run COM/request smoke**

Verify `DllGetClassObject`, `DllCanUnloadNow`, x64 PE, request creation, and runtime startup.

- [ ] **Step 4: Commit**

```bash
git add filedone/src/FileDoneShell.cpp filedone/scripts/build-runtime.ps1 filedone/tests/integration/Run-ShellRuntime-Smoke.ps1
git commit -m "feat: hand Explorer requests to native runtime"
```

### Task 10: Recreate Round 1.2 and Round 2 against the native runtime

**Files:**
- Create: `filedone/tests/integration/Run-Round1.ps1`
- Create: `filedone/tests/integration/Run-Round2.ps1`

**Interfaces:**
- Produces machine-readable JSON plus HTML evidence under `filedone/out/reports/`.

- [ ] **Step 1: Implement the exact Round 1.2 cases**

Required IDs:

```text
R1-01 Unicode + spaces / Make Smaller
R1-02 Japanese + Emoji + alpha / Compatible
R1-03 Fit Under strict <= target
R1-04 Safe to Share removes seeded metadata
R1-05 Read-only source remains untouched
R1-06 Existing output is never overwritten
R1-07 Corrupt input fails cleanly with no fake success artifact
R1-08 Mixed Unicode images -> 3-page PDF
R1-09 Video Compatible = H.264/AAC MP4
R1-10 Video Safe to Share strips metadata
```

- [ ] **Step 2: Implement the exact Round 2 cases**

Required IDs:

```text
R2-01 Near-MAX_PATH Unicode + spaces
R2-02 TIFF alpha -> Compatible PNG
R2-03 AVIF input -> broadly compatible image
R2-04 FLAC -> Compatible MP3
R2-05 WAV -> Smaller MP3
R2-06 Video Make Smaller
R2-07 Video Fit Under strict <= target
R2-08 Already-compatible MP4 is NOOP
R2-09 Concurrent same-input operations are collision-safe
R2-10 Unsupported input fails cleanly with no extra artifact
```

- [ ] **Step 3: Run both rounds locally/CI**

Expected: `10/10 PASS` in each round. Any failure blocks `NATIVE_RUNTIME_PASS`.

- [ ] **Step 4: Commit**

```bash
git add filedone/tests/integration/Run-Round1.ps1 filedone/tests/integration/Run-Round2.ps1
git commit -m "test: restore full native runtime regression gates"
```

### Task 11: Build the semantic Oracle Parity Gate

**Files:**
- Create: `filedone/tests/integration/Run-OracleParity.ps1`
- Create: `filedone/tests/integration/parity-cases.json`

**Interfaces:**
- Produces `filedone/out/reports/oracle-parity.json` and `.html`.

- [ ] **Step 1: Define parity cases with explicit expected semantic fields**

Each case records:

```json
{
  "action": "compatible",
  "inputs": ["..."],
  "targetMb": 0,
  "compare": ["status","outputCount","extension","suffix","originalUnchanged"]
}
```

Include all five actions, NOOP, unsupported, HEIC/HEIF Safe Share, PDF ordering/page count, duplicate naming, and concurrency.

- [ ] **Step 2: Run oracle and native runtime in isolated sibling directories**

Never let either implementation see the other's generated outputs.

- [ ] **Step 3: Compare semantics, not media bytes**

Fit Under may report the intentional stricter-native fix noted in Task 7; all other differences are failures unless the design spec is amended and reapproved.

- [ ] **Step 4: Require full parity PASS**

`ORACLE_PARITY_PASS` requires zero unexplained mismatches.

- [ ] **Step 5: Commit**

```bash
git add filedone/tests/integration/Run-OracleParity.ps1 filedone/tests/integration/parity-cases.json
git commit -m "test: add P1.5.2 semantic parity gate"
```

### Task 12: Add P1.8A CI and freeze the native-runtime gate

**Files:**
- Create: `.github/workflows/filedone-p1-8a-runtime.yml`

**Interfaces:**
- Produces CI artifact `FileDone-P1.8A-native-runtime-x64` containing binaries, hashes, and regression/parity reports.

- [ ] **Step 1: Configure workflow on branch `filedone-p1-8-store`**

Use `windows-2025`, checkout, `ilammy/msvc-dev-cmd@v1` x64, dependency acquisition, runtime build, unit tests, Round 1, Round 2, parity.

- [ ] **Step 2: Add immutable gate checks**

CI must fail if:

```text
oracle SHA differs
FileDoneRuntime.exe missing/not x64
FileDoneShellNative.dll exports missing
Round1 != 10/10
Round2 != 10/10
parity contains unexplained mismatch
shipping runtime source references PowerShell
```

- [ ] **Step 3: Upload evidence and hashes**

Artifact contains `FileDoneRuntime.exe`, `FileDoneShellNative.dll`, tool-version report, SHA-256 list, Round 1/2 reports, parity report.

- [ ] **Step 4: Run CI and require completed/success**

Only this successful run may promote the branch to `NATIVE_RUNTIME_PASS` + `ORACLE_PARITY_PASS`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/filedone-p1-8a-runtime.yml
git commit -m "ci: gate P1.8 native runtime and parity"
```

## P1.8A Completion Criteria

Do not proceed to MSIX packaging until all are true:

- `FileDoneRuntime.exe` is native x64 and launches no PowerShell.
- Shell hands requests directly to the runtime.
- Round 1.2 = `10/10 PASS`.
- Round 2 = `10/10 PASS`.
- Oracle parity has zero unexplained mismatches.
- P1.5.2 oracle hash remains exact.
- Current Cross-PC Win32 rollback package remains untouched.
- CI run is completed/success and evidence artifact hashes are recorded.
