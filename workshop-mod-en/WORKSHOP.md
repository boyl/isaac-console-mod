# Console UI — Workshop copy

Use the description embedded in `metadata.xml` as the canonical Workshop page text.

## 2.5.4-en.10 update note

Steam Deck and Steam Input shoulder controls now support semantic actions plus named physical fallbacks. LB/RB remain repeat-count controls, LT/RT remain focus-aware paging controls, and held analog triggers page only once until released.

## 2.5.4-en.9 update note

Contextual help now reflects the active keyboard, mouse, or controller path. Controller Y pages multi-page descriptions without affecting execution, favorites, repeat count, or list pages. Measured one- or two-line Toasts stay within their background and preserve the cause plus next action for critical messages.

## 2.5.4-en.8 update note

Optional MCM can now keep the menu open after regular commands, retaining the current category, page, selection, and command text for repeated testing. The default remains to close, and lifecycle commands that change the run always close and release input first. User-facing command descriptions now focus on effects and restrictions rather than implementation details.

## 2.5.4-en.7 update note

All 1,162 right-side entries can now be added to Featured with F, controller X, or each card's hollow/filled star. Featured is ordered by most recent favorite, while old saves migrate in their existing catalog order. Command favorites remain references to their original execution contracts and never bypass manual, lifecycle, native-console-only, or blocked safety rules.

## 2.5.4-en.3 update note

Fixed Toasts potentially remaining visible throughout a Rerun after The Lamb. Toast timing no longer depends on an absolute game-frame deadline, and prior-run transient UI state is cleared when the frame counter resets.

## 2.5.4-en.2 update note

Fixed first-open D-pad navigation when Featured is empty; an empty first-process view now starts on the first Collectibles entry, while saved favorites stay in Featured. Directional input prefers runtime menu actions with raw D-pad fallback and does not double-move when both sources report together.

## Publication checklist

- Title: `Console UI`
- Workshop ID: `3779128726`
- In-game version: `2.5.4-en.10`
- Metadata version: `2.5.4.10`
- Visibility: Public
- Tags: Lua, Tweaks
- Required items: none; EID is optional
- Confirm the uploader targets `3779128726`, not the Chinese item `3776882944`
- Confirm the preview includes `CONSOLE UI` and `EN`; compare it with the current remote preview before uploading, because development copies may be stale

