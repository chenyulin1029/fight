# FileDone — Microsoft Store Release Checklist

## Current release boundary

FileDone core shipping binaries remain anchored to the validated P1.8B shipping MSIX:
- Source workflow run: 35692146360
- Source MSIX SHA256: 6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE
- Runtime, Shell DLL, Bridge, controlled FFmpeg/ffprobe, and minimal ImageMagick are not rebuilt by the Store RC pipeline.
- Store packaging is identity-only repackaging plus manifest validation and payload hash parity.

## Partner Center identity — external blocker

Reserve the FileDone product name in Partner Center, then open Product management -> Product identity.

Copy these values exactly:
1. Package/Identity/Name
2. Package/Identity/Publisher
3. Package/Properties/PublisherDisplayName

Do not invent or normalize these values. They are case-sensitive.

## Store package build

Run the GitHub workflow:
FileDone Store RC Packaging

Use workflow_dispatch and provide the three Partner Center identity values.

Version rules:
- four numeric parts
- Major must be non-zero
- every part must be 0..65535
- fourth part must be 0 for the package submitted to Microsoft Store

The workflow must emit:
- FILEDONE_STORE_IDENTITY_PASS
- FILEDONE_STORE_PAYLOAD_PARITY_PASS
- FILEDONE_STORE_NO_QA_RESIDUE_PASS
- FILEDONE_STORE_MSIXUPLOAD_PASS
- FILEDONE_STORE_RC_PACKAGE_PASS
- FILEDONE_REAL_STORE_IDENTITY_GATE_PASS

The output artifact must contain:
- FileDone_<version>_x64_Store.msix
- FileDone_<version>_x64.msixupload
- STORE_RC_AUTHORITY.json

## Required pre-certification gates

1. Windows App Certification Kit (WACK) PASS on the exact Store RC package.
2. Partner Center package validation accepts the exact .msixupload.
3. Private audience / package flight install from Microsoft Store succeeds.
4. Human Explorer Gate on the Store-signed build:
   - FileDone appears in the modern Windows 11 first-level context menu.
   - Exact five subcommands:
     - Make Compatible
     - Make Smaller
     - Fit Under...
     - Safe to Share
     - Make PDF
   - Single-file actions produce valid outputs.
   - Fit Under UI accepts a target and output remains under the requested size.
   - Multi-selection Make PDF produces one PDF with the expected page order.
   - Uninstall removes the package registration cleanly.
5. Test at least one lower-spec x64 Windows 11 PC in addition to the primary development PC.

## Store listing / policy requirements

Prepare:
- app description
- category
- age rating questionnaire
- at least one screenshot
- Store logo
- privacy policy
- support contact
- pricing / markets
- certification notes

FileDone is a Desktop Bridge / Win32 product. A privacy policy must be supplied for Store submission.

## Production rule

The Microsoft Store submission package is intentionally not developer-signed. Microsoft Store signs/re-signs the MSIX during certification/publishing.

Do not ship:
- FileDone.QAUnsigned identity
- FileDone.QATestSigned identity
- QA Root / QA leaf certificates
- .pfx/.p12/private keys
- Human Gate test files

## Release labels

Do not call the product Store Release Candidate until the real Partner Center identity package exists.

Do not call it Store Human PASS until the Microsoft Store-installed build passes the Explorer Human Gate.

Do not call it Production PASS until Store certification completes and the published package is rechecked from the public/private Store channel.
