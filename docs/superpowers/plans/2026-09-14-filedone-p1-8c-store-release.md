# FileDone P1.8C Store Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the already-passing P1.8B MSIX into a complete Microsoft Store submission, reach `SUBMISSION_READY`, submit it, and only promote to `STORE_READY` after Microsoft certification succeeds.

**Architecture:** P1.8C does not change runtime behavior. It freezes the exact P1.8B candidate, prepares Partner Center identity/listing/legal metadata and certification evidence around that same MSIX SHA-256, then treats Microsoft certification as the final external gate.

**Tech Stack:** Microsoft Partner Center, Microsoft Store MSIX submission, Store listing metadata/assets, Windows package/certification validation, GitHub release evidence/docs.

**Spec:** `docs/superpowers/specs/2026-09-14-filedone-p1-8-store-release-design.md`

## Global Constraints

- Begin only after `NATIVE_RUNTIME_PASS`, `ORACLE_PARITY_PASS`, `PACKAGED_RUNTIME_PASS`, `CROSS_PC_MSIX_PASS`, and `DEPENDENCY_LICENSE_PASS` are recorded.
- Store model is paid one-time purchase, no trial, Windows 11 x64 only.
- No subscription, FileDone cloud account, independent updater, Windows 10 package, ARM64 package, or self-signed public distribution is added in P1.8C.
- The MSIX submitted to Partner Center must be byte-identical to the candidate whose final release evidence was approved; if any shipping byte changes, package gates must be rerun as required.
- `SUBMISSION_READY` does not mean `STORE_READY`.
- `STORE_READY` can only be recorded after Microsoft Store certification accepts the package.

---

## File Structure

- `filedone/release/store-product.json` — exact reserved Store identity/product metadata exported into repo-friendly fields.
- `filedone/release/listing/en-US.md` — canonical English Store listing copy.
- `filedone/release/listing/zh-TW.md` — canonical Traditional Chinese Store listing copy.
- `filedone/release/legal/privacy.md` — privacy statement source text.
- `filedone/release/legal/support.md` — support-page source text.
- `filedone/release/legal/third-party-notices.md` — release copy of dependency notices.
- `filedone/release/release-manifest.json` — exact shipping package/binary/tool hashes and version.
- `filedone/release/SUBMISSION_CHECKLIST.md` — human submission checklist with pass/fail evidence fields.
- `filedone/release/CERTIFICATION_RESULT.md` — certification result record; created only after Microsoft returns a result.
- `filedone/scripts/verify-release-candidate.ps1` — final immutable-candidate verifier.
- `.github/workflows/filedone-p1-8c-release.yml` — final release evidence workflow.

### Task 1: Reserve and record the Microsoft Store product identity

**Files:**
- Create: `filedone/release/store-product.json`
- Verify: `filedone/package/StoreIdentity.json`

**Interfaces:**
- Produces exact Partner Center identity values consumed by the manifest renderer and submission checklist.

- [ ] **Step 1: Reserve the FileDone product name in Partner Center using the individual developer account**

The reserved product must be the product intended for public commercial release, not a test product.

- [ ] **Step 2: Record exact identity values**

`store-product.json` must contain the exact Partner Center values for:

```json
{
  "ProductDisplayName": "FileDone",
  "PackageIdentityName": "actual reserved identity name",
  "Publisher": "actual Partner Center publisher string",
  "PublisherDisplayName": "actual verified individual publisher display name",
  "DistributionModel": "paid-one-time",
  "Trial": false,
  "SupportedArchitectures": ["x64"],
  "MinimumOS": "Windows 11"
}
```

The literal values for identity/publisher must be copied from Partner Center, not invented locally.

- [ ] **Step 3: Cross-check package identity**

`filedone/package/StoreIdentity.json` and `store-product.json` must agree exactly for package identity/publisher fields.

- [ ] **Step 4: Commit**

```bash
git add filedone/release/store-product.json filedone/package/StoreIdentity.json
git commit -m "release: record Microsoft Store identity"
```

### Task 2: Finalize Store listing copy and legal/support pages

**Files:**
- Create: `filedone/release/listing/en-US.md`
- Create: `filedone/release/listing/zh-TW.md`
- Create: `filedone/release/legal/privacy.md`
- Create: `filedone/release/legal/support.md`
- Create: `filedone/release/legal/third-party-notices.md`

**Interfaces:**
- Produces canonical text used for Store listing fields and public support/privacy URLs.

- [ ] **Step 1: Write product description using outcome language**

Required user-visible concepts:

```text
Right-click files in Windows 11.
Make Compatible.
Make Smaller.
Fit Under X MB.
Safe to Share.
Make PDF.
Processing stays local on the PC.
Original files are left untouched by default.
```

Do not mention internal phase names, C++, COM, PowerShell, FFmpeg architecture, registry, package identity, or QA gates in listing copy.

- [ ] **Step 2: Write pricing/trial wording**

Listing/support text must clearly align with one-time purchase and no free trial; do not promise subscription features or cloud services.

- [ ] **Step 3: Write privacy statement**

State exactly what the shipping product does: local file processing, no FileDone account, no cloud conversion requirement, and what local diagnostic data is written if any. Do not claim zero data collection unless the final package has been audited to support that exact claim.

- [ ] **Step 4: Mirror required third-party notices**

Copy the exact approved dependency notices from P1.8B release evidence; no dependency version/license may silently diverge.

- [ ] **Step 5: Commit**

```bash
git add filedone/release/listing filedone/release/legal
git commit -m "docs: prepare FileDone Store listing and legal copy"
```

### Task 3: Freeze the exact release candidate and generate a release manifest

**Files:**
- Create: `filedone/scripts/verify-release-candidate.ps1`
- Create: `filedone/release/release-manifest.json`

**Interfaces:**
- Produces one immutable release evidence record binding package version and SHA-256 values.

- [ ] **Step 1: Define release-manifest fields**

Required fields:

```json
{
  "PackageVersion": "monotonically increasing four-part MSIX version",
  "MsixSha256": "exact hash",
  "ShellDllSha256": "exact hash",
  "RuntimeExeSha256": "exact hash",
  "FfmpegSha256": "exact hash",
  "FfprobeSha256": "exact hash",
  "MagickSha256": "exact hash",
  "GitCommit": "exact source commit",
  "NativeRuntimeGate": "PASS",
  "OracleParityGate": "PASS",
  "PackagedRuntimeGate": "PASS",
  "CrossPcMsixGate": "PASS",
  "DependencyLicenseGate": "PASS"
}
```

- [ ] **Step 2: Make verifier recompute every hash from release artifacts**

The script must fail if the package version does not match the rendered manifest or if any hash differs.

- [ ] **Step 3: Ban forbidden shipping content again**

Unpack the exact release MSIX and fail on PowerShell/VBS/CMD/BAT, Bridge, test oracle, cert/private-key files, DevShell/QAUnsigned strings.

- [ ] **Step 4: Record source commit and make dirty-source builds invalid**

The release workflow must fail if the candidate was produced from uncommitted source changes.

- [ ] **Step 5: Commit**

```bash
git add filedone/scripts/verify-release-candidate.ps1 filedone/release/release-manifest.json
git commit -m "release: freeze FileDone Store candidate"
```

### Task 4: Run final certification preflight

**Files:**
- Create: `filedone/release/SUBMISSION_CHECKLIST.md`
- Create: `.github/workflows/filedone-p1-8c-release.yml`

**Interfaces:**
- Produces final preflight evidence artifact and a human-readable checklist.

- [ ] **Step 1: Re-run immutable candidate verification in CI**

No rebuilding after this point unless a failure requires a new version/candidate.

- [ ] **Step 2: Run package validation/certification tooling available on the Windows runner**

Capture results for manifest validity, package integrity, architecture, installation, launch/runtime smoke, uninstall, and API/package checks relevant to the submitted desktop MSIX.

- [ ] **Step 3: Verify Store metadata completeness**

Checklist must explicitly cover:

```text
reserved product identity
paid one-time pricing configured
no trial configured
Windows 11 x64 availability
package uploaded
Store description
screenshots/assets
privacy URL
support URL
third-party notices
age/category fields required by Partner Center
release notes/version
```

- [ ] **Step 4: Verify all technical gates are linked to evidence**

Each PASS must name the report/artifact/run that proves it. A typed `PASS` without evidence does not count.

- [ ] **Step 5: Commit**

```bash
git add filedone/release/SUBMISSION_CHECKLIST.md .github/workflows/filedone-p1-8c-release.yml
git commit -m "ci: add Store submission readiness gate"
```

### Task 5: Perform Partner Center submission without changing the candidate

**Files:**
- Modify only evidence fields in: `filedone/release/SUBMISSION_CHECKLIST.md`

**Interfaces:**
- Produces Partner Center submission identifier/date and the final `SUBMISSION_READY` evidence state.

- [ ] **Step 1: Upload the exact MSIX whose SHA-256 is in `release-manifest.json`**

Recompute the hash immediately before upload and compare it to the release manifest.

- [ ] **Step 2: Configure commercial availability**

Set one-time paid acquisition, no trial, Windows 11 x64 scope according to the approved product model.

- [ ] **Step 3: Populate Store listing from committed canonical copy**

Do not freestyle materially different claims in Partner Center.

- [ ] **Step 4: Submit for certification**

Record submission date and Partner Center submission/reference identifier in `SUBMISSION_CHECKLIST.md`.

- [ ] **Step 5: Promote only to `SUBMISSION_READY`**

At this point the project status is exactly `SUBMISSION_READY`, not `STORE_READY`.

- [ ] **Step 6: Commit evidence update**

```bash
git add filedone/release/SUBMISSION_CHECKLIST.md
git commit -m "release: record FileDone Store submission"
```

### Task 6: Handle Microsoft certification result truthfully

**Files:**
- Create: `filedone/release/CERTIFICATION_RESULT.md`

**Interfaces:**
- Produces the final status record and, if accepted, `STORE_READY` authority.

- [ ] **Step 1: Record Microsoft's actual result verbatim in structured form**

Required fields:

```text
Submission reference
Package version
MSIX SHA-256
Certification status
Certification completion timestamp
Certification notes/failures if supplied
```

- [ ] **Step 2: If certification fails, do not relabel the candidate**

Create a new corrective work item/branch from the failure evidence. Any shipping-byte change requires a new package version and re-entry through the affected technical gates.

- [ ] **Step 3: If certification succeeds, verify Store availability state**

Confirm the certified package is the expected version/identity and is available according to the configured release schedule.

- [ ] **Step 4: Promote to `STORE_READY` only on success**

The status record must explicitly say:

```text
STORE_READY
Microsoft Store certification: ACCEPTED
Package SHA-256: <exact release manifest hash>
```

- [ ] **Step 5: Commit**

```bash
git add filedone/release/CERTIFICATION_RESULT.md
git commit -m "release: record Microsoft Store certification result"
```

## P1.8C Completion Criteria

`SUBMISSION_READY` requires all of the following:

- Real Store reservation/identity recorded and matched to the MSIX manifest.
- Paid one-time purchase, no trial, Windows 11 x64 product configuration prepared.
- Canonical Store listing/privacy/support/third-party notices complete.
- Exact release candidate frozen by version and hashes.
- Technical P1.8A/P1.8B gates linked to evidence.
- Final package validation/certification preflight passes.
- Exact release MSIX uploaded to Partner Center without mutation.

`STORE_READY` additionally requires:

- Microsoft Store certification result is ACCEPTED.
- Accepted package version and SHA-256 match the frozen release candidate.
- The certified listing/package is available according to the intended release settings.

Nothing earlier may be described as `STORE_READY`.
