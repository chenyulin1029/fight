# FileDone P1.8B MSIX Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the already-passing native FileDone runtime into a Windows 11 x64 Store-oriented MSIX with bundled media tools and first-layer `IExplorerCommand` integration, then reach `PACKAGED_RUNTIME_PASS` and `CROSS_PC_MSIX_PASS`.

**Architecture:** Treat P1.8A binaries as immutable inputs to packaging. Build a reproducible package layout with `FileDoneShellNative.dll`, `FileDoneRuntime.exe`, fixed tool binaries, assets, license notices, and a generated manifest whose shipping identity comes only from the reserved Microsoft Store product. QA packaging may use CI-only install mechanics, but no DevShell/QAUnsigned identity or self-signed route is accepted as a shipping path.

**Tech Stack:** MSIX/AppxManifest, `makeappx.exe`, Windows 11 x64, GitHub Actions Windows runners, packaged COM `windows.comServer`, `windows.fileExplorerContextMenus`, Win32 full-trust app, PowerShell only for build/QA automation.

**Spec:** `docs/superpowers/specs/2026-09-14-filedone-p1-8-store-release-design.md`

## Global Constraints

- Do not begin this plan until P1.8A has `NATIVE_RUNTIME_PASS` and `ORACLE_PARITY_PASS`.
- Shipping package is Windows 11 x64 only; minimum OS remains `10.0.22000.0` or later.
- Shipping MSIX must not contain `FileDoneCore.ps1`, any dispatcher PowerShell script, `FileDoneBridge.exe`, DevShell identity, QAUnsigned identity, `.cer`, or `.pfx` files.
- Final Store identity values must come from the actual Microsoft Store reservation.
- The shell DLL and runtime behavior may not be modified merely to make packaging tests pass; packaging failures must be fixed in packaging/integration unless a real runtime defect is proven.
- Bundled tools must be fixed by version and SHA-256 and must pass the dependency license gate before shipping.

---

## File Structure

- `filedone/third_party/lock.json` — exact bundled tool versions, source URLs, SHA-256, license classification.
- `filedone/third_party/NOTICE.md` — generated human-readable dependency notices.
- `filedone/scripts/acquire-tools.ps1` — download/verify exact locked tool binaries for CI/dev packaging.
- `filedone/scripts/verify-dependency-license.ps1` — inspect FFmpeg build flags and required license files.
- `filedone/package/AppxManifest.template.xml` — Store-ready manifest template without hard-coded dev identity.
- `filedone/package/StoreIdentity.json` — real reserved Store identity values, committed only after reservation.
- `filedone/package/Assets/` — final Store/app assets.
- `filedone/scripts/build-msix.ps1` — deterministic package-layout and makeappx build.
- `filedone/tests/package/Verify-PackageLayout.ps1` — static package-content gate.
- `filedone/tests/package/Verify-PackagedRuntime.ps1` — install/register/COM/tool/runtime smoke.
- `filedone/tests/package/Verify-UpdateUninstall.ps1` — version upgrade, uninstall, reinstall checks.
- `.github/workflows/filedone-p1-8b-msix.yml` — package integration CI.

### Task 1: Lock exact FFmpeg/FFprobe/ImageMagick binaries and licensing evidence

**Files:**
- Create: `filedone/third_party/lock.json`
- Create: `filedone/scripts/acquire-tools.ps1`
- Create: `filedone/scripts/verify-dependency-license.ps1`
- Create: `filedone/third_party/NOTICE.md`

**Interfaces:**
- Produces verified `filedone/vendor/tools/ffmpeg.exe`, `ffprobe.exe`, `magick.exe` for packaging.
- Produces a machine-readable dependency report under `filedone/out/reports/dependencies.json`.

- [ ] **Step 1: Select an FFmpeg build that proves LGPL-compatible configuration**

Acceptance logic must execute:

```powershell
$conf = (& filedone/vendor/tools/ffmpeg.exe -hide_banner -buildconf 2>&1) -join "`n"
if($conf -match '--enable-gpl'){ throw 'GPL-enabled FFmpeg build is rejected for P1.8 initial Store release' }
if($conf -match '--enable-nonfree'){ throw 'nonfree FFmpeg build is rejected' }
```

Record exact version, source URL, SHA-256, license `LGPL-2.1-or-later` or the verified upstream classification, and build configuration in `lock.json`.

- [ ] **Step 2: Select ImageMagick build and record delegates**

Run `magick -version`, capture version/features/delegates, hash the exact binary set required at runtime, and include all license files copied from the selected distribution.

- [ ] **Step 3: Make acquisition hash-locked**

`acquire-tools.ps1` must download only URLs present in `lock.json` and fail before extraction/use if SHA-256 differs.

- [ ] **Step 4: Generate NOTICE evidence**

`NOTICE.md` must list dependency name, exact version, homepage/source, license name, and shipped license filename. It must not claim license compliance merely because the binaries run.

- [ ] **Step 5: Commit**

```bash
git add filedone/third_party filedone/scripts/acquire-tools.ps1 filedone/scripts/verify-dependency-license.ps1
git commit -m "build: lock Store runtime dependencies"
```

### Task 2: Replace the old dev manifest with a Store-identity template and strict validator

**Files:**
- Replace: `filedone/package/AppxManifest.xml` with `filedone/package/AppxManifest.template.xml`
- Create: `filedone/package/StoreIdentity.schema.json`
- Create after reservation: `filedone/package/StoreIdentity.json`
- Create: `filedone/scripts/render-manifest.ps1`
- Create: `filedone/tests/package/Verify-Manifest.ps1`

**Interfaces:**
- Consumes exact Store reservation values: `Name`, `Publisher`, `PublisherDisplayName`.
- Produces rendered `filedone/pkg/AppxManifest.xml`.

- [ ] **Step 1: Write failing manifest tests against current QA identity**

The validator must reject all of these strings anywhere in a shipping manifest:

```text
FileDone.QAUnsigned
FileDone.DevShell
CN=FileDone QA
OID.2.25.311729368913984317654407730594956997722=1
```

- [ ] **Step 2: Define Store identity schema**

Required JSON keys:

```json
{
  "Name": "string",
  "Publisher": "string",
  "PublisherDisplayName": "string"
}
```

No sample identity is accepted by `render-manifest.ps1`; missing file is a hard block for shipping build.

- [ ] **Step 3: Create the manifest template**

Keep:

```text
ProcessorArchitecture=x64
TargetDeviceFamily Windows.Desktop MinVersion=10.0.22000.0
uap10:RuntimeBehavior=win32App
uap10:TrustLevel=mediumIL
rescap:runFullTrust
windows.comServer surrogate class CLSID 72E5C740-AB37-4FD8-94E8-4DE0ECA292B5
windows.fileExplorerContextMenus -> desktop5:ItemType Type="*"
```

Application executable becomes `FileDoneRuntime.exe`, not Bridge.

- [ ] **Step 4: Render and validate manifest**

Use XML APIs, not string replacement for structure. Tests verify identity fields exactly match `StoreIdentity.json` and no rejected dev strings remain.

- [ ] **Step 5: Commit template/validator**

```bash
git add filedone/package filedone/scripts/render-manifest.ps1 filedone/tests/package/Verify-Manifest.ps1
git commit -m "build: template Store MSIX identity"
```

### Task 3: Build deterministic package layout with no PowerShell shipping payload

**Files:**
- Create: `filedone/scripts/build-msix.ps1`
- Create: `filedone/tests/package/Verify-PackageLayout.ps1`
- Create: `filedone/package/Assets/*`

**Interfaces:**
- Produces `filedone/out/FileDone_<version>_x64.msix` and `filedone/out/package-manifest.json` containing hashes of every shipping file.

- [ ] **Step 1: Write package-layout tests before build script**

Required files:

```text
AppxManifest.xml
FileDoneShellNative.dll
FileDoneRuntime.exe
tools/ffmpeg.exe
tools/ffprobe.exe
tools/magick.exe
THIRD_PARTY_NOTICES/...
Assets/Square44x44Logo.png
Assets/Square150x150Logo.png
```

Forbidden extensions/names:

```text
*.ps1
*.vbs
*.cmd
*.bat
*.cer
*.pfx
FileDoneBridge.exe
FileDoneCore.ps1
```

- [ ] **Step 2: Implement package staging**

Copy P1.8A CI-approved binaries by explicit path, copy only the locked tool payload, render manifest, copy notices/assets, and generate SHA-256 inventory.

- [ ] **Step 3: Build with Windows SDK `makeappx.exe`**

Run:

```powershell
& $makeappx pack /d filedone/pkg /p filedone/out/FileDone_$Version`_x64.msix /o
if($LASTEXITCODE -ne 0){ throw "makeappx failed: $LASTEXITCODE" }
```

- [ ] **Step 4: Unpack the result and re-run layout verification on the actual MSIX contents**

Do not trust the staging directory alone.

- [ ] **Step 5: Commit**

```bash
git add filedone/scripts/build-msix.ps1 filedone/tests/package/Verify-PackageLayout.ps1 filedone/package/Assets
git commit -m "build: create deterministic Store MSIX"
```

### Task 4: Verify packaged COM activation and runtime/tool resolution in CI

**Files:**
- Create: `filedone/tests/package/Verify-PackagedRuntime.ps1`
- Modify: `filedone/runtime/Toolchain.cpp` only if a proven package-relative resolution bug exists.

**Interfaces:**
- Produces packaged smoke evidence JSON with package registration, COM activation, file presence, runtime execution, and output verification.

- [ ] **Step 1: Install/register the QA candidate only in isolated CI**

Use a CI-supported sideload/test mechanism appropriate to the rendered QA candidate; this mechanism is test infrastructure and must not appear in shipping instructions or the Store package.

- [ ] **Step 2: Verify package registration and installed files**

Check installed location contains exact hashed runtime/shell/tool binaries.

- [ ] **Step 3: Activate the CLSID**

```powershell
$t=[Type]::GetTypeFromCLSID([Guid]'{72E5C740-AB37-4FD8-94E8-4DE0ECA292B5}')
$o=[Activator]::CreateInstance($t)
if(-not$o){ throw 'Packaged shell COM activation failed' }
```

- [ ] **Step 4: Execute a packaged runtime request using files outside the package**

Confirm output is created beside the source, logs/requests go to writable user locations, and no write occurs under the package install directory.

- [ ] **Step 5: Remove package and confirm registration disappears**

- [ ] **Step 6: Commit**

```bash
git add filedone/tests/package/Verify-PackagedRuntime.ps1
git commit -m "test: verify packaged FileDone runtime"
```

### Task 5: Prove Windows 11 first-layer shell contract after packaging

**Files:**
- Create: `filedone/tests/package/Verify-ExplorerContract.ps1`
- Create: `filedone/tests/package/HUMAN_GATE_P1_8B.md`

**Interfaces:**
- Automated evidence proves manifest/COM/selection request contract; one human gate proves actual first-layer menu visibility and action behavior.

- [ ] **Step 1: Automated manifest/COM checks**

Verify the registered package exposes `windows.fileExplorerContextMenus` for `Type="*"`, matching CLSID, and the DLL is x64 with required COM exports.

- [ ] **Step 2: Automated true-selection request test**

Use the existing shell selection proof pattern to prove single selection and a 3-item ordered selection reach `FileDoneRuntime.exe` intact.

- [ ] **Step 3: Run one human Explorer gate only after all automated steps pass**

Required human observations:

```text
H1 FileDone appears in the Windows 11 first-layer context menu
H2 Make Smaller on one Unicode-named image creates exactly one expected output
H3 Make PDF on exactly three selected originals creates one 3-page PDF in selection order
```

No human debugging/registry/compiler steps are permitted.

- [ ] **Step 4: Record PASS/FAIL as evidence, never infer PASS from automation**

- [ ] **Step 5: Commit**

```bash
git add filedone/tests/package/Verify-ExplorerContract.ps1 filedone/tests/package/HUMAN_GATE_P1_8B.md
git commit -m "test: add packaged Explorer first-layer gate"
```

### Task 6: Prove version update, uninstall, reinstall, and stale-state cleanup

**Files:**
- Create: `filedone/tests/package/Verify-UpdateUninstall.ps1`
- Create: `filedone/tests/package/TestVersions.json`

**Interfaces:**
- Produces install/update/uninstall/reinstall report for two consecutive package versions.

- [ ] **Step 1: Build two test versions with monotonically increasing versions**

Example test sequence only:

```text
3.0.0.0 -> 3.0.1.0
```

Both packages contain identical runtime behavior; the second version exists to prove package update mechanics.

- [ ] **Step 2: Clean install first version**

Verify COM activation and one action.

- [ ] **Step 3: Update to second version**

Verify package version changed, context menu remains functional, writable data remains valid, runtime/tool hashes match v2 package.

- [ ] **Step 4: Uninstall**

Verify package, COM registration, and shell extension disappear. User outputs beside source files must remain; temporary FileDone request artifacts must not be left in an active state.

- [ ] **Step 5: Reinstall v2 and rerun action smoke**

- [ ] **Step 6: Commit**

```bash
git add filedone/tests/package/Verify-UpdateUninstall.ps1 filedone/tests/package/TestVersions.json
git commit -m "test: gate MSIX update and uninstall lifecycle"
```

### Task 7: Run Cross-PC MSIX validation on two clean Windows 11 x64 environments

**Files:**
- Create: `filedone/tests/package/CROSS_PC_MSIX_GATE.md`
- Create: `filedone/scripts/collect-package-evidence.ps1`

**Interfaces:**
- Produces two independent machine reports with OS version, package version, package hash, runtime hash, shell hash, action results, update/uninstall results.

- [ ] **Step 1: Define machine-cleanliness precheck**

Reject a machine/environment if the target package is already installed or stale FileDone dev identities are registered.

- [ ] **Step 2: Run the same package candidate on clean environment A**

Require install, packaged runtime smoke, Explorer contract, update, uninstall, reinstall.

- [ ] **Step 3: Run the same package candidate on clean environment B**

Use the exact same MSIX SHA-256; rebuilding between machines invalidates this gate.

- [ ] **Step 4: Compare reports**

Both must PASS. Any machine-specific workaround blocks promotion until incorporated into a clean reproducible package fix.

- [ ] **Step 5: Commit evidence schema/scripts**

```bash
git add filedone/tests/package/CROSS_PC_MSIX_GATE.md filedone/scripts/collect-package-evidence.ps1
git commit -m "test: define cross-PC MSIX promotion gate"
```

### Task 8: Add P1.8B CI and promotion evidence

**Files:**
- Create: `.github/workflows/filedone-p1-8b-msix.yml`

**Interfaces:**
- Produces artifact `FileDone-P1.8B-MSIX-x64` with MSIX, hashes, manifest, dependency report, package reports.

- [ ] **Step 1: Gate workflow on successful P1.8A inputs**

Workflow must rebuild from the same source commit or download a recorded P1.8A artifact whose hashes are verified before packaging.

- [ ] **Step 2: Run ordered gates**

```text
dependency acquisition + SHA verification
license configuration verification
manifest render/validation
MSIX build
actual MSIX unpack/layout validation
packaged registration/COM/runtime smoke
update/uninstall lifecycle
```

- [ ] **Step 3: Publish hashes and reports**

- [ ] **Step 4: Require human first-layer gate and two clean-environment reports before promotion**

CI success alone is `PACKAGE_CI_PASS`, not `PACKAGED_RUNTIME_PASS` or `CROSS_PC_MSIX_PASS`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/filedone-p1-8b-msix.yml
git commit -m "ci: gate P1.8 Store package integration"
```

## P1.8B Completion Criteria

All must be true before Store-submission work begins:

- Exact FFmpeg/ImageMagick binaries are hash-locked and license evidence is recorded.
- Shipping MSIX contains no PowerShell/VBS/CMD/BAT, Bridge, oracle core, dev certificate, or dev identity.
- Real reserved Store identity is rendered into the shipping manifest.
- Packaged COM activation succeeds.
- Package-relative tools execute successfully.
- Windows 11 first-layer FileDone menu receives one-file and true 3-file selections correctly.
- Update/uninstall/reinstall lifecycle passes.
- Same MSIX SHA passes on two clean Windows 11 x64 environments.
- `PACKAGED_RUNTIME_PASS`, `CROSS_PC_MSIX_PASS`, and `DEPENDENCY_LICENSE_PASS` evidence are separately recorded.
