# Console UI Workshop release

## Before upload

1. Build the clean allowlisted package with `tools-en/build_workshop_package.ps1`.
2. Run the English validator and all mock scenarios.
3. Close the game and install the staged directory as `mods/console_ui_workshop`.
4. Disable Isaac Chinese Console so it does not compete for F6 or L3.
5. Test Repentance, Repentance+, and REPENTOGON with EID both disabled and enabled.
6. Capture the runtime version, font route, catalog count, layout signature, and command results from a fresh `log.txt`.

## Update the existing Workshop item

1. Keep the game closed and open the official `tools/ModUploader/ModUploader.exe`.
2. Select the staged `outputs-en/console_ui_workshop` directory.
3. Confirm the uploader targets the English item ID `3779128726`, not the Chinese item ID `3776882944`.
4. Compare the staged preview with the current remote preview. Do not assume a development copy is current; if they differ, preserve or recover the remote image before uploading.
5. Upload the staged directory, not the ZIP or repository root.
6. Use the matching entry from `CHANGELOG.md` as the update note.

## After publication

Verify the remote title, description, visibility, tags, required items, version, and preview. Refresh or resubscribe, compare the subscribed copy with the staged package, and run both supported runtimes again. If the English release regresses, make only the English item non-public while preparing a corrected package.

