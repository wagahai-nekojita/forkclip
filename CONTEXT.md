# Forkclip

Forkclip captures and reuses local clipboard history while protecting private clipboard content from casual disclosure.

## Language

**Clipboard Item**:
A saved clipboard entry that can be reused later. A Clipboard Item may have one current **Display Title**.
_Avoid_: history row, clip, card

**Private Clipboard Item**:
A Clipboard Item whose content should not be shown in history previews. It may have a **Display Title** so the user can recognize it without revealing the content.
_Avoid_: secret row, hidden card

**Display Title**:
A user-authored label for recognizing a Clipboard Item without changing the clipboard content itself.
_Avoid_: title edit, content title, alias

**Auto Paste**:
An optional behavior that copies a selected Clipboard Item and then attempts to paste it into the app and focused element that were active before Forkclip opened.
_Avoid_: instant paste, direct insert

**Portfolio Source Repository**:
A public repository intended to show Forkclip's source, documentation, validation evidence, screenshots, and design context for portfolio evaluation. It is not a channel for prebuilt app downloads.
_Avoid_: release repo, download repo, app distribution

**Development Repository**:
A private repository used for ongoing Forkclip development, including work-in-progress history and local workflow material that is not part of portfolio presentation.
_Avoid_: public repo, clean repo

**Public App Distribution**:
A distribution form where general users can download and run a prebuilt Forkclip app. Public App Distribution is distinct from a **Portfolio Source Repository**.
_Avoid_: source release, portfolio publish

**Public Portfolio CI**:
Lightweight public validation for a **Portfolio Source Repository** that demonstrates the source can be built and tested from GitHub. It is not release validation for **Public App Distribution**.
_Avoid_: release CI, distribution validation, notarization check

**Publicization Gate**:
The final review point before changing the **Portfolio Source Repository** from private to public. It includes source, documentation, screenshots, tracked files, and workflow-log review because repository contents and prior Actions logs become public after the visibility change.
_Avoid_: publish click, release gate, deployment

## Example Dialogue

Dev: "Should editing a private item's title change what gets copied?"

Domain expert: "No. The Display Title is only a label; the Clipboard Item content remains unchanged."

Dev: "Where does Auto Paste send the item?"

Domain expert: "Back to the previously focused app or field; if that paste attempt fails, the Clipboard Item should still be copied."

Dev: "Does publishing Forkclip on GitHub mean we should attach a downloadable app?"

Domain expert: "No. For a Portfolio Source Repository, reviewers should evaluate the source and build instructions; Public App Distribution is a separate decision."

Dev: "Can the same repository serve ongoing development and portfolio presentation?"

Domain expert: "No. The Development Repository stays private, while the Portfolio Source Repository is recreated cleanly for public evaluation."

Dev: "Does a passing public CI badge mean Forkclip is ready for public app distribution?"

Domain expert: "No. Public Portfolio CI shows source reproducibility; distribution readiness would require separate release validation."

Dev: "Can we make the portfolio repository public as soon as CI passes?"

Domain expert: "No. The Publicization Gate must review repository contents and workflow logs before visibility changes."
