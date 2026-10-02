# FileDone Microsoft Store Submission Checklist

## Frozen product authority
- [x] Shipping MSIX run 35692146360.
- [x] Shipping MSIX SHA256 6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE.
- [x] Runtime / controlled FFmpeg / minimal ImageMagick machine gates passed.
- [x] Store RC preserves frozen shipping payload hashes.
- [x] Store-only package replaces legacy FileDoneBridge.exe with dedicated FileDoneStoreEntry.exe.

## Store package structural gate
- [x] Synthetic Store Preview package builds.
- [x] Manifest Identity / Publisher / Version rewrite is gated.
- [x] Store version format A.B.C.0 is enforced.
- [x] Dedicated Store entry is DPI-aware and portable.
- [x] Preview authority: FILEDONE_STORE_RC_STRUCTURAL_PREVIEW_MACHINE_PASS.
- [ ] Final Partner Center identity authority: FILEDONE_STORE_RC_PACKAGE_MACHINE_PASS.

## Partner Center exact values — hard blocker
- [ ] Package/Identity/Name
- [ ] Package/Identity/Publisher
- [ ] Publisher display name
- [ ] Product name reservation / product exists in Partner Center
Do not guess any of these values. Manual-dispatch the Store RC workflow with exact case and punctuation.

## Active-user WACK — hard blocker
- [ ] Extract Store RC artifact on an interactive Windows session.
- [ ] Run RUN_STORE_WACK_GATE.cmd.
- [ ] Require WACK XML OVERALL_RESULT=PASS.
- [ ] Require FILEDONE_STORE_WACK_ACTIVE_USER_MACHINE_PASS.
- [ ] Preserve FileDone-Store-WACK-Evidence.zip.

## Real Store / Explorer Human Gate — hard blocker
- [ ] Install a Store-signed/private-audience build, not an abandoned QA sideload package.
- [ ] FileDone appears in the first Windows 11 Explorer context menu.
- [ ] Exactly five subcommands appear.
- [ ] Make Compatible output verified.
- [ ] Make Smaller output verified.
- [ ] Safe to Share output verified.
- [ ] Fit Under... target MB and output verified.
- [ ] Three selected images produce exactly one three-page PDF in selection order.
- [ ] Store entry launch behavior verified.
- [ ] Update and uninstall behavior verified.

## Store listing
- [x] zh-TW listing draft.
- [x] en-US listing draft.
- [x] Applicable license terms draft.
- [x] Privacy policy source draft.
- [ ] Publisher-controlled HTTPS privacy-policy URL.
- [ ] Publisher-controlled HTTPS support URL.
- [ ] At least one real screenshot; FileDone release bar is four or more.
- [ ] Required Store logo/listing assets uploaded.
- [ ] Age rating, category, pricing, markets, system requirements and certification notes completed.

## Release authority
Store submission candidate = exact Partner Center identity package PASS + active-user WACK PASS + Store/private-audience Explorer Human PASS + required listing assets/URLs.
Public production PASS only after Microsoft certification and final Store-install verification.