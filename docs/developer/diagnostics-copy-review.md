# Diagnostics Copy Review

## Reviewed Surface

The review covered diagnostics-facing copy in:

- `ClipboardStatusFormatter`
- `DiagnosticsPanel`
- formatter tests that pin diagnostics-visible status and banner wording

## Copy Changes

The copy keeps the current Japanese UI language and avoids localization infrastructure. Changes are limited to clarity and actionability:

- replaces terse failure labels like `異常` and `欠落` with state descriptions such as `利用不可`, `見つかりません`, and `確認失敗`
- clarifies skip reasons such as excluded applications, concealed pasteboard markers, and unsupported formats
- changes fetch failure banner copy to say that there are histories that cannot be decrypted
- makes the recovery action explicit that it backs up the existing DB and initializes history with a new encryption key
- expands diagnostics panel labels from short internal terms such as `DB` and `changeCount` to user-facing labels

## Non-goals

This review does not add localization infrastructure, change diagnostics state models, change recovery behavior, or alter clipboard capture behavior.

Future copy changes should stay at formatter/helper boundaries and include focused tests when the wording represents user-critical state.
