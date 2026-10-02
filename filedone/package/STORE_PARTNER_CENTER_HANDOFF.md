# FileDone — Partner Center handoff

This is the only manual account step required before FileDone can produce a real Microsoft Store submission package.

## 1. Reserve the product name

Partner Center -> Apps and games -> New product -> MSIX or PWA app.

Reserve:

FileDone

Do not create an EXE/MSI product. FileDone's release path is MSIX.

## 2. Copy the real product identity

Open the FileDone product:

Product management -> Product identity / View app identity details.

Copy these values exactly, preserving case and punctuation:

- Package/Identity/Name
- Package/Identity/Publisher
- Package/Properties/PublisherDisplayName

Do not invent or normalize them. Do not reuse FileDone.QAUnsigned, FileDone.QATestSigned, FileDone.StorePreview, or any Contoso preview identity.

## 3. Return the three values

The Store RC workflow requires:

- identity_name = Package/Identity/Name
- publisher = Package/Identity/Publisher
- publisher_display_name = Package/Properties/PublisherDisplayName
- version = 2.0.2.0

The final workflow must emit:

- FILEDONE_STORE_WACK_PASS
- FILEDONE_STORE_RC_SUBMISSION_PACKAGE_PASS
- FILEDONE_STORE_RC_SUBMISSION_MACHINE_PASS

A push-triggered preview uses a synthetic identity and must never be submitted to Partner Center.

## 4. Store signing boundary

For MSIX distributed through Microsoft Store, FileDone does not need a CA-trusted production signing certificate for submission. Microsoft Store re-signs the package after certification.

Any temporary self-signed certificate used by CI exists only to let Windows/WACK validate the package on the disposable runner. It is not a production trust authority and no private key/certificate material may ship inside the package.

## 5. After Partner Center accepts the package

Next release gates:

1. Partner Center package validation accepts the exact Store RC package.
2. Configure a restricted/private test audience before public release.
3. Install the Store-delivered build on a normal Windows 11 account.
4. Run the Explorer Human Gate:
   - FileDone appears in the modern first-level context menu.
   - exact five subcommands appear.
   - Make Compatible / Make Smaller / Safe to Share produce valid outputs.
   - Fit Under... respects the requested limit.
   - multi-select Make PDF produces one correctly ordered PDF.
   - uninstall removes the package cleanly.
5. Re-run on the lower-spec x64 validation PC.
