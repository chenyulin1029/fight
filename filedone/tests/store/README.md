# FileDone Store Release Candidate

This directory is the Store-specific release path. It deliberately does not reuse the QA self-signed sideload identity as a production authority.

## Authority

- Binary payload source: exact shipping MSIX from GitHub Actions run 35692146360.
- Shipping MSIX SHA256: 6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE.
- Store repack may change only package identity metadata and package/signature container metadata. Runtime, Shell DLL, Bridge, FFmpeg, FFprobe, and ImageMagick payload hashes must remain unchanged.
- Windows 10/11 Store version must be A.B.C.0; the fourth component is reserved for Store use.

## Final submission inputs

Obtain these exact values from Partner Center > Product management > Product identity / View app identity details:

- Package/Identity Name
- Publisher
- Publisher display name

Values are case-sensitive and punctuation-sensitive. Do not guess them.

Then manually dispatch `.github/workflows/filedone-store-rc.yml` with those values and a version such as `2.0.2.0`.

## Gates

A final artifact is a Store submission candidate only when the workflow emits:

- `FILEDONE_STORE_WACK_PASS`
- `FILEDONE_STORE_RC_SUBMISSION_PACKAGE_PASS`
- `FILEDONE_STORE_RC_SUBMISSION_MACHINE_PASS`

Push-triggered artifacts use a synthetic preview identity and are structural previews only. They must never be submitted to Partner Center.