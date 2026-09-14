# FileDone P1.8 Store Release Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the approved P1.8 Store-first migration in three independently reviewable phases without ever sacrificing the proven Cross-PC Win32 rollback authority.

**Architecture:** P1.8 is split because native-runtime migration, MSIX/package integration, and Store submission are independently rejectable subsystems. Execute P1.8A first; after its hard gates pass, reserve the Store identity and execute P1.8B; execute P1.8C only after package/cross-PC/license gates pass.

**Tech Stack:** C++17/Win32/MSVC x64 for runtime and shell, FFmpeg/FFprobe/ImageMagick CLI engines, Windows 11 x64 MSIX, GitHub Actions Windows CI, Microsoft Partner Center.

**Spec:** `docs/superpowers/specs/2026-09-14-filedone-p1-8-store-release-design.md`

## Global Constraints

- Store-first, paid one-time purchase, no trial, Windows 11 x64 only.
- Shipping runtime contains no PowerShell execution path.
- Shipping package contains no P1.5.2 oracle, Bridge, VBS/CMD/BAT, self-signed public-distribution certificate, or rejected DevShell/QAUnsigned identity.
- Frozen P1.5.2 oracle SHA-256 remains `6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD`.
- Original files remain untouched by default.
- `STORE_READY` is forbidden until Microsoft Store certification accepts the exact frozen release candidate.
- Current Cross-PC Win32 baseline remains rollback authority throughout P1.8.

---

## Authoritative Self-Review Corrections

These corrections resolve two issues found while reviewing the detailed subplans and override conflicting wording there:

1. P1.8A remains **C++17**. `BuildActionMutexName` must use:

```cpp
std::wstring BuildActionMutexName(
    Action action,
    const std::vector<std::wstring>& canonicalPaths);
```

Do not use `std::span`, which is C++20.

2. The real Microsoft Store product reservation happens **at the start of P1.8B Task 2**, before rendering the Store manifest. P1.8C Task 1 therefore verifies/records that already-reserved identity; it must not create a second product reservation.

3. QA signing/sideload mechanics are test infrastructure only. They may never become customer install instructions or shipping assets. The public distribution path is Microsoft Store.

## Ordered Execution

### Phase A — Native Runtime

Detailed plan:
`docs/superpowers/plans/2026-09-14-filedone-p1-8a-native-runtime.md`

- [ ] Implement test-only frozen oracle and native build skeleton.
- [ ] Implement request parsing, path policy, unique naming, process-safe mutexes.
- [ ] Implement direct `CreateProcessW` tool execution and media probes.
- [ ] Port Compatible, Smaller, Safe to Share, Make PDF, Fit Under.
- [ ] Implement native Fit Under target-size dialog, private logs, consumer notices.
- [ ] Change Explorer shell handoff from Bridge to `FileDoneRuntime.exe`.
- [ ] Re-run Round 1.2 and Round 2, each requiring 10/10 PASS.
- [ ] Run semantic Oracle Parity with zero unexplained mismatch.
- [ ] Require successful P1.8A CI evidence artifact.

**Phase A exit:** `NATIVE_RUNTIME_PASS` + `ORACLE_PARITY_PASS`.

### Phase B — Store Identity + MSIX Integration

Detailed plan:
`docs/superpowers/plans/2026-09-14-filedone-p1-8b-msix-integration.md`

- [ ] Lock exact FFmpeg/FFprobe/ImageMagick versions, hashes, and licenses.
- [ ] Reserve the real FileDone product name/identity in Partner Center and write the exact `Name`, `Publisher`, and `PublisherDisplayName` into `filedone/package/StoreIdentity.json`.
- [ ] Replace the rejected QA manifest identity with a Store-identity-driven template.
- [ ] Build deterministic x64 MSIX containing only native FileDone binaries, tools, assets, and notices.
- [ ] Verify actual unpacked MSIX contains no PowerShell/VBS/CMD/BAT, Bridge, oracle, dev cert, or rejected identity.
- [ ] Verify packaged COM activation and package-relative tools.
- [ ] Verify Windows 11 first-layer FileDone menu with one-file and true three-file human gates after automation passes.
- [ ] Verify update/uninstall/reinstall lifecycle.
- [ ] Run the same MSIX SHA on two clean Windows 11 x64 environments.

**Phase B exits:** `PACKAGED_RUNTIME_PASS` + `CROSS_PC_MSIX_PASS` + `DEPENDENCY_LICENSE_PASS`.

### Phase C — Submission / Certification

Detailed plan:
`docs/superpowers/plans/2026-09-14-filedone-p1-8c-store-release.md`

- [ ] Verify and record the already-reserved Store product identity; do not reserve another product.
- [ ] Finalize Store listing, privacy, support, and third-party notice text.
- [ ] Freeze exact release candidate version and all SHA-256 values.
- [ ] Run final package/certification preflight without rebuilding the candidate afterward.
- [ ] Upload the exact frozen MSIX to Partner Center.
- [ ] Configure paid one-time purchase, no trial, Windows 11 x64 availability.
- [ ] Submit for certification and record submission evidence.
- [ ] Stop at `SUBMISSION_READY` while certification is pending.
- [ ] Record Microsoft's real certification result.
- [ ] Promote to `STORE_READY` only if certification is accepted and the accepted package version/hash match the frozen candidate.

## Failure / Rollback Rules

- A Phase A regression returns work to the last passing P1.8A commit; it never modifies the stable Cross-PC Win32 authority.
- A Phase B package failure does not justify changing native behavior unless a reproducible native defect is proven by P1.8A tests.
- A dependency license failure blocks shipping even if functional tests pass.
- A Microsoft certification failure remains a failure. Fixes create a new package version and rerun every gate affected by changed shipping bytes.
- CI success cannot substitute for explicitly required human Explorer/Store gates.

## Completion State Machine

```text
P1.7 CROSS-PC CLEAN INSTALL PASS
  -> NATIVE_RUNTIME_PASS
  -> ORACLE_PARITY_PASS
  -> PACKAGED_RUNTIME_PASS
  -> CROSS_PC_MSIX_PASS
  -> DEPENDENCY_LICENSE_PASS
  -> SUBMISSION_READY
  -> Microsoft certification ACCEPTED
  -> STORE_READY
```

No state may be skipped or inferred from a later-looking artifact.
