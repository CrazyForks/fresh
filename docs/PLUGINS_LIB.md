# Plugins Lib Notes

Status and next steps for reusing and extending `plugins/lib`.

## Existing Helpers (usable now)
- `PanelManager`: open/close a virtual-buffer panel in a split, remember the source split/buffer, update content.
- `NavigationController<T>`: manage a selected index with wrap, status updates, and selection-change callback.
- `VirtualBufferFactory`: thin helpers for creating virtual buffers (current split, existing split, or new split) with sensible defaults.

## Completed Refactors

### Plugins now using PanelManager + NavigationController:
- `find_references.ts` - uses `PanelManager` for panel lifecycle and `NavigationController` for reference selection
- `search_replace.ts` - uses `PanelManager` for panel lifecycle and `NavigationController` for result management

### Moved to tests/plugins (sample/example code):
- `diagnostics_panel.ts` - refactored to use lib, moved since it uses dummy sample data (not real LSP diagnostics)

### Not refactored (different architecture):
- `git_log.ts` - uses a multi-view stacking pattern (log → commit detail → file view) where buffers are swapped within the same split. This doesn't fit `PanelManager`'s single-panel model. Could benefit from `VirtualBufferFactory` for buffer creation, but the complexity is in view state management and highlighting.

## Remaining Low-Impact Refactors
- Prompt-driven pickers (`git_grep.ts`, `git_find_file.ts`) could share a tiny prompt helper in `plugins/lib/` instead of wiring three prompt event handlers and result caches in each plugin. (Helper not written yet; see below.)

## Missing Primitives (would simplify mature plugins)
- Git:
  - `editor.gitDiff({ path, against? }): Array<{ type: "added" | "modified" | "deleted"; startLine: number; lineCount: number }>` or a higher-level `editor.setLineIndicatorsFromGitDiff(bufferId, opts)` to replace `git_gutter.ts`'s diff parsing.
  - `editor.gitBlame({ path, commit? }): BlameBlock[]` (hash/author/summary/line ranges) to replace porcelain parsing and block grouping in `git_blame.ts`.
  - `editor.gitFiles(): string[]` and `editor.gitGrep(query, opts): GitGrepResult[]` to drop custom spawn/parse in git find/grep/search-replace.
- Prompt convenience:
  - `PromptController` helper (could live in `plugins/lib`) that owns `startPrompt`, `prompt_changed/confirmed/cancelled` wiring, and suggestion cache. This would collapse the repeated glue in git grep/find-file into a few lines.
- Line/byte ergonomics:
  - Line-based virtual line helper (`addVirtualLineAtLine` or `byteOffsetAtLine`) so blame headers don't need custom byte-offset tables.
  - Possibly a `setOverlaysForLines` helper to batch per-line overlays/indicators.

## Next Actions
1) ~~Refactor the list-based plugins to use `PanelManager` + `NavigationController`~~ ✓ Done
2) Add a `PromptController` to `plugins/lib` and adopt it in `git_grep.ts` / `git_find_file.ts`.
3) Design editor-level git helpers (diff/blame/files/grep) and line-position helpers; once added, simplify `git_gutter.ts` and `git_blame.ts` around them.
