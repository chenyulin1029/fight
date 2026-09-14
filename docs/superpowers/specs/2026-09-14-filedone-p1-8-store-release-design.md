# FileDone P1.8 — Microsoft Store Release Packaging Design

Date: 2026-09-14
Status: Design approved in chat; implementation not started
Branch: `filedone-p1-8-store`

## 1. Objective

P1.8 converts the already proven FileDone Win32 product behavior into a Microsoft Store-first shipping architecture without changing the product's user-facing semantics.

The release target is:

- Microsoft Store first.
- One-time paid purchase.
- No trial.
- Windows 11 x64 only.
- MSIX package submitted through Partner Center.
- Windows 11 first-layer FileDone context menu through packaged `IExplorerCommand` integration.
- No PowerShell dependency in the shipping runtime.
- FFmpeg, FFprobe, and ImageMagick bundled inside the package.
- Microsoft Store signing/update path rather than self-signed or unsigned QA package distribution.

P1.8 is a runtime and packaging migration, not a feature redesign.

## 2. Existing Authority and Rollback Baseline

The current rollback authority remains the proven FileDone stable Win32 baseline that passed the Cross-PC Clean Install Gate.

The frozen legacy behavior authority remains the P1.5.2 Engine Core:

`SHA-256 6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD`

The legacy PowerShell core is retained only as a regression oracle during P1.8 development. It must not ship in the final Store package.

If the P1.8 native runtime migration fails any hard gate, the product rolls back to the proven Cross-PC Win32 baseline. P1.8 work must never overwrite or invalidate that rollback authority.

## 3. Product Model

The first commercial Store release is intentionally simple:

- Paid, one-time purchase.
- No subscription.
- No free trial.
- No FileDone account system.
- No cloud processing requirement.
- Windows 11 x64 only.
- Local file processing.
- Original source files remain untouched by default.

Windows 10 support is explicitly out of scope for P1.8.

## 4. Shipping Architecture

The final runtime chain is:

`Windows 11 Explorer`
→ `FileDoneShellNative.dll`
→ `FileDoneRuntime.exe`
→ bundled `ffmpeg.exe` / `ffprobe.exe` / `magick.exe`
→ output next to the user's source file

### 4.1 FileDoneShellNative.dll

Responsibilities:

- Implement the packaged Windows 11 `IExplorerCommand` shell extension.
- Receive the real `IShellItemArray` selection from Explorer.
- Expose the FileDone root command and five subcommands.
- Validate only lightweight eligibility required to render/enable commands.
- Serialize the selected paths and requested action into a request contract.
- Launch or hand off to `FileDoneRuntime.exe` quickly.

Non-responsibilities:

- No media conversion.
- No heavy probing.
- No long-running work inside Explorer.
- No PowerShell launch.

### 4.2 FileDoneRuntime.exe

`FileDoneRuntime.exe` is the new native C++ shipping orchestration layer.

Responsibilities:

- Parse and validate the shell request.
- Preserve Explorer selection order.
- Resolve output names safely.
- Preserve the existing concurrency and collision semantics.
- Run FFmpeg, FFprobe, and ImageMagick as child processes with controlled arguments.
- Implement action-specific orchestration.
- Verify output completion before declaring success.
- Remove partial/failed outputs when appropriate.
- Emit consumer-safe messages while retaining private technical logs for support.

The runtime must not invoke PowerShell.

### 4.3 Bundled Engines

The package contains fixed, tested versions of:

- `tools\ffmpeg.exe`
- `tools\ffprobe.exe`
- `tools\magick.exe`

The user must not be asked to install WinGet packages, FFmpeg, ImageMagick, Visual Studio, compilers, or any other external dependency.

The tool versions used for a Store submission are immutable for that release and recorded in release metadata.

## 5. File and Data Locations

MSIX installation content is treated as read-only shipping content.

Runtime-writable data must live outside the installed package in the user's writable app data/temp space. This includes:

- requests,
- logs,
- temporary files,
- QA state,
- support diagnostics,
- transient conversion artifacts.

The runtime must never attempt to modify files inside the installed WindowsApps package directory.

Outputs created by FileDone are written beside the original source file according to the existing output naming contract.

## 6. Five Action Behavior Contracts

P1.8 must reproduce the established product behavior. It must not invent new policies while porting to C++.

### 6.1 Make Compatible

- Determine media type using the existing compatibility rules.
- Use ImageMagick for supported image conversions where appropriate.
- Use FFmpeg for supported audio/video conversions where appropriate.
- Keep the existing output format policy.
- Never overwrite the original source file.

### 6.2 Make Smaller

- Images use ImageMagick.
- Video/audio use FFmpeg.
- Preserve the established compression behavior and output naming rules.
- Do not turn this action into a user-configurable codec/settings dialog in P1.8.

### 6.3 Fit Under X MB

This is a high-risk action and requires strict behavioral parity.

- Support the existing eligible image/video inputs.
- Preserve the current iterative target-size semantics.
- Output must actually be at or below the requested upper bound according to the same acceptance rule used by the established regression suite.
- A merely smaller file is not a PASS.
- A failure must not masquerade as success.

### 6.4 Safe to Share

- Preserve existing metadata/privacy-oriented behavior.
- Preserve the proven HEIC/HEIF → JPG behavior.
- Do not introduce new destructive cleanup rules during the port.

### 6.5 Make PDF

- Accept image selections only.
- Preserve the actual Explorer multi-selection order.
- Produce one PDF from the selected inputs.
- Output page count must match accepted input count.
- Preserve existing output naming semantics.

## 7. Shared Runtime Contracts

All five actions must preserve these cross-cutting behaviors:

- Unicode paths.
- Chinese, Japanese, and emoji filenames.
- Long paths supported by the established product scope.
- Original files untouched.
- Deterministic unique output naming.
- No accidental overwrite.
- Named-mutex or equivalent process-safe concurrency control.
- Same action + same input must not race output naming/creation.
- Different inputs/actions may proceed concurrently when safe.
- Explorer multi-selection order preserved.
- Partial failed outputs must not be mistaken for successful results.
- Unsupported/no-op conditions must produce the same product-level outcome category as the legacy behavior authority.
- Consumer UI must not expose compiler, COM, registry, package, PowerShell, diagnostic-path, or internal gate terminology.

## 8. Oracle Parity Strategy

The P1.5.2 PowerShell Core becomes a test oracle only.

For the parity suite, the same controlled inputs are processed by:

1. the frozen legacy P1.5.2 behavior authority, and
2. the new native `FileDoneRuntime.exe`.

Parity is semantic, not byte-for-byte. The comparison checks:

- output count,
- output type/extension,
- naming behavior,
- PDF page count,
- selection order,
- strict Fit Under result,
- Safe to Share format behavior,
- success/failure category,
- original-file preservation,
- collision/concurrency behavior.

Byte-identical media output is not required unless a specific regression test explicitly requires it.

## 9. Microsoft Store / MSIX Architecture

The Store package contains at minimum:

- `FileDoneShellNative.dll`
- `FileDoneRuntime.exe`
- `tools\ffmpeg.exe`
- `tools\ffprobe.exe`
- `tools\magick.exe`
- required runtime libraries if any
- application assets/icons
- license and third-party notice files
- Store/MSIX manifest

The final manifest uses the real Microsoft Store-reserved package identity and publisher values. Development identities such as `FileDone.DevShell` or `FileDone.QAUnsigned` are forbidden in a shipping submission.

The manifest registers:

- packaged COM server support for the shell handler, and
- Windows File Explorer context-menu integration for the Windows 11 first-layer FileDone command.

Self-signed development certificates and the prior unsigned-package QA mechanism are not shipping paths.

## 10. Store Distribution Model

The Store listing is configured as:

- Paid.
- One-time purchase.
- No trial.
- Windows 11 x64 only.

Microsoft Store handles end-user package signing/distribution and update delivery for the submitted package.

P1.8 does not implement an independent updater.

## 11. Third-Party Licensing Gate

No dependency enters the shipping MSIX until its exact binary build and license obligations are recorded.

### 11.1 FFmpeg

The selected FFmpeg build must be compatible with FileDone's commercial distribution model.

Release policy:

- Do not use a build enabled with GPL components for the initial FileDone Store release.
- Do not use a build enabled with nonfree components.
- Record the exact FFmpeg version and build configuration.
- Ship the required license notices and source/build information required by the selected FFmpeg licensing configuration.

### 11.2 ImageMagick

- Record exact ImageMagick version/build.
- Preserve required ImageMagick license/attribution notices.
- Verify bundled delegates are also license-compliant before packaging.

A release cannot pass the Dependency License Gate merely because the binaries execute correctly.

## 12. Testing and Promotion Gates

P1.8 promotion is sequential. A later gate cannot overwrite or excuse a failed earlier gate.

### Gate 1 — `NATIVE_RUNTIME_PASS`

The new C++ runtime must rerun the full functional regression, including at minimum:

- all five actions,
- Unicode/Chinese/Japanese/emoji paths,
- long paths,
- HEIC/HEIF/TIFF/AVIF image coverage,
- audio/video coverage,
- strict Fit Under behavior,
- PDF page count and order,
- no-op cases,
- unsupported cases,
- duplicate output naming,
- concurrency/race behavior,
- original-file preservation.

Legacy P1.5.2 PASS results cannot be inherited for the new runtime.

### Gate 2 — `ORACLE_PARITY_PASS`

The native runtime must pass the semantic parity suite against the frozen P1.5.2 behavior oracle.

### Gate 3 — `PACKAGED_RUNTIME_PASS`

The real packaged chain must pass:

`Explorer → packaged shell DLL → FileDoneRuntime.exe → bundled tools`

This includes:

- Windows 11 first-layer context menu visibility,
- single-selection action,
- true multi-selection action,
- multi-page PDF,
- Explorer restart,
- logout/login persistence,
- package-relative tool resolution,
- writable runtime-data separation from package files.

### Gate 4 — `CROSS_PC_MSIX_PASS`

The package must be exercised on at least two clean Windows 11 x64 environments beyond the main development machine.

Required flows:

- clean install,
- first launch/use,
- all critical context-menu scenarios,
- update from an earlier P1.8 package version,
- uninstall,
- reinstall,
- no stale package/COM/shell state that breaks subsequent installation.

### Gate 5 — `DEPENDENCY_LICENSE_PASS`

Exact FFmpeg/ImageMagick builds and all bundled delegates pass the release compliance review and required notices are present.

### Gate 6 — `SUBMISSION_READY`

Before Partner Center upload:

- final Store identity is present,
- versioning is valid,
- assets are complete,
- manifest validates,
- package architecture/minimum OS are correct,
- COM/File Explorer declarations are correct,
- install/update/uninstall tests pass,
- local package/certification validation passes,
- Privacy URL, Support URL, Store listing text, pricing, and required legal notices are complete.

`SUBMISSION_READY` means the package is ready to submit. It does not mean Microsoft has certified it.

### Gate 7 — `STORE_READY`

`STORE_READY` may only be claimed after Microsoft Store certification accepts the release package.

A local CI PASS, a local MSIX install PASS, or a Partner Center upload alone is not enough to claim `STORE_READY`.

## 13. Release / Versioning Policy

P1.8 introduces explicit product versioning for Store packages.

Rules:

- Every Store submission uses a monotonically increasing package version.
- A release records hashes for FileDone native binaries and bundled third-party tools.
- A failed candidate is never reused by silently replacing binaries under the same release identity.
- QA/dev identities and shipping identities remain separated.

## 14. Consumer Experience

The intended end-user experience is:

1. Buy FileDone once in Microsoft Store.
2. Install from Store.
3. Right-click one or more supported files in Windows 11 Explorer.
4. Select FileDone from the first-layer context menu.
5. Choose the desired action.
6. Receive the result beside the original file.

No separate main application window is required for normal daily use.

No command prompt, PowerShell window, compiler, WinGet, dependency installer, or developer terminology is exposed to the customer.

## 15. Non-Goals for P1.8

The following are explicitly out of scope:

- Windows 10 support.
- ARM64 support.
- Subscription billing.
- Free trial logic.
- FileDone cloud accounts.
- Cloud conversion.
- A new desktop dashboard/main app experience.
- Rewriting FFmpeg/ImageMagick internals.
- Direct library integration with FFmpeg/ImageMagick in the first Store release.
- New codecs/options unrelated to parity with the proven FileDone behavior.
- Self-signed public distribution.
- Unsigned public distribution.

## 16. Implementation Boundary

P1.8 implementation must proceed in this order:

1. Build native runtime behavior outside Store packaging.
2. Reach `NATIVE_RUNTIME_PASS`.
3. Reach `ORACLE_PARITY_PASS`.
4. Package the proven runtime into the Store/MSIX architecture.
5. Reach `PACKAGED_RUNTIME_PASS`.
6. Reach `CROSS_PC_MSIX_PASS`.
7. Complete dependency compliance and Store submission materials.
8. Reach `SUBMISSION_READY`.
9. Submit to Microsoft Store.
10. Only after Microsoft certification, mark the release `STORE_READY`.

Packaging work must not be used to hide or bypass a native-runtime regression failure.
