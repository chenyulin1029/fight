# FileDone — Microsoft Store Listing Draft

## Name
FileDone

## Short description
Practical file actions directly in Windows 11 File Explorer.

## Description
FileDone adds a compact set of file-processing actions directly to Windows File Explorer so common conversion and size-management tasks can be started from the context menu without opening a separate editor.

Available actions:
- Make Compatible
- Make Smaller
- Fit Under...
- Safe to Share
- Make PDF

FileDone processes selected files on the Windows device and writes the result back as a new local file.

## Feature bullets
- Windows 11 File Explorer integration
- Five focused file actions from one context menu
- Local file processing
- Target-size workflow with Fit Under...
- Multi-file Make PDF workflow
- No account required
- No advertising or analytics SDK in the current release candidate

## Suggested category
Utilities & tools

## Certification notes draft
FileDone is a packaged Win32/Desktop Bridge application using a packaged COM IExplorerCommand shell extension.

Primary Explorer entry:
Right-click a supported file in Windows 11 File Explorer -> FileDone.

The FileDone submenu contains:
Make Compatible / Make Smaller / Fit Under... / Safe to Share / Make PDF.

Fit Under... opens a small target-size dialog.

The application uses bundled FFmpeg/ffprobe and ImageMagick components and does not download processing tools at runtime.

## Assets still required before submission
- Partner Center-reserved product identity
- Store logo in required Partner Center sizes
- at least one Store screenshot
- privacy policy public URL
- support contact / support URL
- final pricing and market availability
