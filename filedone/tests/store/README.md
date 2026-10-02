# FileDone Store Release Candidate

QA self-signed sideload packages are not production authority.

## Frozen authority
- Shipping source is the exact MSIX from GitHub Actions run 35692146360.
- Shipping SHA256: 6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE.
- Frozen Runtime, Shell DLL, FFmpeg, FFprobe and ImageMagick payload hashes must survive Store repack unchanged.
- Store-only packaging replaces obsolete FileDoneBridge.exe with FileDoneStoreEntry.exe; Explorer actions still flow through packaged COM to FileDoneRuntime.exe.
- Store package version is A.B.C.0.

## Partner Center identity
Final package requires exact Package/Identity/Name, Package/Identity/Publisher and Publisher display name from Partner Center. These are case- and punctuation-sensitive and must never be guessed.
Push builds use synthetic FileDone.StorePreview and must never be submitted. Manual dispatch with exact Partner Center values creates a final-identity RC.

## Independent authorities
GitHub package structural preview: FILEDONE_STORE_RC_STRUCTURAL_PREVIEW_MACHINE_PASS
Final Partner Center identity package: FILEDONE_STORE_RC_PACKAGE_MACHINE_PASS
Interactive Windows WACK: FILEDONE_STORE_WACK_ACTIVE_USER_MACHINE_PASS

Only final identity package PASS + active-user WACK PASS + Store/private-audience Explorer Human PASS is a Store submission candidate.