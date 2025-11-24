# View-Centric Rewrite Plan (Spec by Module)

This document captures the final architecture for rewriting the remaining byte-centric modules into the new view-centric model. All public APIs must use `ViewPosition`/`ViewEventPosition`/`ViewEventRange` and only consult source bytes via `Layout` when needed. No buffer-first fallbacks.

## Progress Summary (Last Updated: 2025-11-24 Evening)

**IMPORTANT:** Commits 267037b and 8cc3742 accidentally added code for pre-refactored APIs and were reverted.

**Completed Core Modules:**
- ✅ position_history.rs - Fully view-centric
- ✅ word_navigation.rs - View helpers implemented
- ✅ viewport.rs - Uses top_view_line (but has top_byte remnants to fix)
- ✅ status_bar.rs - Displays view positions
- ✅ split_rendering.rs - Renders from Layout
- ✅ navigation/action_convert.rs - Core actions + word nav + line ops
- ✅ navigation/layout_nav.rs - Pure layout navigation (has one top_byte ref to fix)
- ✅ navigation/edit_map.rs - View→source mapping
- ✅ navigation/mapping.rs - Mapping helpers

**Type Updates Completed:**
- ✅ editor/types.rs - SearchState, Bookmark, InteractiveReplaceState use ViewEventPosition
- ✅ editor/types.rs - MouseState uses drag_start_top_view_line instead of top_byte

**Remaining Work (235 compilation errors):**

### High Priority - Core Infrastructure
1. **editor/input.rs** (~60 errors)
   - Remove references to non-existent Action variants (OpenFile, SaveAll, etc)
   - Remove calls to removed methods (file_dialog, save_all, hide_popup, etc)
   - Fix handle_action to only use existing Actions
   - Many editor methods were removed during refactoring

2. **editor/mod.rs** (~120 errors)
   - Missing methods: collect_lsp_changes, clear_search_highlights, update_search_highlights
   - Missing methods: notify_lsp_save, add_overlay, remove_overlay, ensure_active_tab_visible
   - Event struct issues: missing source_range field, wrong field names
   - ViewEventPosition/ViewEventRange need comparison operators and len()
   - Selection/cursor tuple access (.start, .end) - need proper struct
   - viewport.top_byte references (should be top_view_line)

3. **cursor.rs & multi_cursor.rs** (~15 errors)
   - cursor.column field access (Cursor needs to expose column or use accessors)
   - ViewPosition arithmetic operations
   - Selection tuple .start/.end access

4. **split.rs** (~20 errors)
   - viewport.top_byte references
   - SplitRenderer::apply_wrapping_transform removed
   - Type mismatches with ViewPosition

5. **state.rs** (~10 errors)
   - adjust_cursors_for_insert/delete functions missing
   - VirtualTextManager adjust_for_insert/delete methods missing
   - viewport.top_byte reference

6. **script_control.rs** (~6 errors)
   - handle_mouse method removed from Editor

7. **ui/split_rendering.rs** (~5 errors)
   - SplitRenderer::temporary_split_state removed
   - AnsiBackground::render_background removed
   - Theme field names changed (gutter_fg, gutter_bg, text_fg)

8. **viewport.rs** (~1 error)
   - Anonymous lifetime issue

### Pattern of Errors
Most errors fall into these categories:
1. **Removed methods/fields**: Many Editor methods were removed during refactoring
2. **top_byte → top_view_line**: Incomplete migration of viewport
3. **ViewPosition/ViewEventPosition operations**: Need comparison, arithmetic, Display
4. **Event struct changes**: Missing or renamed fields
5. **Selection/cursor representation**: Tuples → proper structs needed

**Key Change:** `navigation::action_convert::action_to_events()` now takes `&Buffer` parameter for word navigation.

**Next Steps:**
1. Fix viewport.top_byte → top_view_line everywhere
2. Implement comparison/arithmetic for ViewPosition types
3. Add Display impl for ViewEventPosition
4. Create proper Selection struct instead of tuples
5. Restore or stub removed Editor methods that are actually needed
6. Clean up editor/input.rs to remove dead code

---

## position_history.rs
- **Purpose:** VS Code–style back/forward navigation over cursor moves.
- **Types:**
  - `PositionEntry { buffer_id: BufferId, position: ViewEventPosition, anchor: Option<ViewEventPosition> }`
  - `PositionHistory` semantics unchanged (coalesce small moves; commit on buffer switch/large jump/back/forward).
- **Behavior:**
  - `record_movement(buffer_id, pos, anchor)`: view positions only; coalesce using view-space distance (line/column deltas or buffer change triggers commit).
  - `commit_pending_movement`, `push`, `back`, `forward`, `can_go_back/forward`, `current`, `clear`, `len`, `is_empty` stay conceptually identical.
- **Notes:** No byte math anywhere.

## word_navigation.rs
- **Purpose:** Word boundary helpers.
- **API split:**
  - Keep pure byte-level helpers (`is_word_char`, `find_word_start_bytes`, `find_word_end_bytes`).
  - Buffer-aware byte helpers remain (`find_word_start`, `find_word_end`, `find_word_start_left/right`, `find_completion_word_start`) for source-byte contexts.
  - Add view helpers: `find_word_start_view`, `find_word_end_view`, `find_word_start_left_view`, `find_word_start_right_view`, `find_completion_word_start_view` that map view → source via layout, scan bytes, then map back; if mapping missing, stay put or operate on visible text window.
- **Semantics:** Same word rules and completion deletion rules (`.`/`::` stop deletion); entry points in the editor must call view helpers.

## viewport.rs
- **Purpose:** Scrolling/visible-region tracking.
- **State:** Replace `top_byte` with `top_view_line` (keep `left_column`, `width/height`, offsets, wrap flag). Optionally cache `top_source_byte` as a hint only.
- **Behavior:**
  - `visible_line_count`, `resize`, `set_scroll_offset` unchanged in concept.
  - `gutter_width` can take optional `Layout` (or total_view_lines) to size digits; buffer-based estimate is a fallback.
  - `scroll_up/down(lines)` operate on view lines, clamped to `layout.total_view_lines`.
  - `set_view_top(line)` enforces bounds using `layout.total_view_lines`.
  - `ensure_visible_in_layout(cursor, layout, gutter_width)`: uses view_line/column + scroll offsets to adjust `top_view_line`; no byte iteration.
  - Loading/prep: if data needs to be prefetched, use layout.source_range hints; scrolling math stays view-line based.
- **Notes:** Eliminate `saturating_sub` on positions; columns are separate fields.

## ui/split_rendering.rs
- **Purpose:** Render splits using `Layout` and view-centric cursors.
- **Inputs:** `Layout` for the split, `Viewport` (`top_view_line`), cursors (view positions), overlays/margins.
- **Behavior:**
  - Slice layout lines for the viewport (`[top_view_line .. top_view_line + height]`).
  - Gutter numbers: use `line.source_byte` to derive buffer line numbers when available; blank for view-only lines.
  - Cursor/selection: render directly from view_line/column; multi-cursor via `Cursors::iter()`.
  - Overlays/virtual text: if source-anchored, map via layout to current view lines before drawing.
  - Logging: log primary cursor as view position (or `ViewEventPosition`), not bytes.
- **Notes:** Remove byte math and `Vec<usize>` collectors expecting cursor positions; use view coords or mapped bytes explicitly.

## ui/status_bar.rs
- **Purpose:** Show cursor position/mode/file info.
- **Behavior:**
  - Primary display: view line/column (1-based for UX).
  - Optional secondary: source line/column if `cursor.source_byte` maps via layout/buffer.
  - No buffer iterators with view positions; resolve source via layout first.
  - Multi-cursor count: use `cursors.len()` (add helper on `Cursors` if needed).

## editor/render.rs
- **Purpose:** Main render loop, search, LSP change collection, nav history.
- **Action conversion:** Already delegated to `navigation::action_convert`.
- **Rewrites:**
  - LSP change collection: consume view-centric events; send LSP edits only when `source_range` is present; skip/flag otherwise.
  - Search find-next/prev: map view cursor → source byte via layout, run buffer search, map hits back to view positions; move cursor with view events.
  - Position history: record `ViewEventPosition`/anchor, not bytes.
  - Highlight/selection refresh: accept view ranges; map to source for overlays via layout.
  - Viewport/cursor sync: entirely view-coordinate + layout-based.
- **Logging:** Use `{:?}` for view positions or implement Display; no byte formatting.

## editor/input.rs
- **Purpose:** Input handling, prompts, popups, macro play/record.
- **Rewrites:**
  - Goto line/prompt: resolve line → target view_line via layout (or buffer line → source byte → layout); emit `MoveCursor` with `ViewEventPosition`; sync viewport via layout.
  - Completion confirm: use view word helpers; deletes use `ViewEventRange` + optional `source_range`; inserts carry `ViewEventPosition`.
  - Position history recording: feed view positions/anchors.
  - Any viewport comparisons must use view_line vs viewport bounds (no `top_byte`).
  - Mouse/block selections: view-based; disable or rewrite consistently.
- **Notes:** No byte-based cursor math remains.

## split.rs (SplitViewState)
- **Viewport:** store `top_view_line`; rebuild layout accordingly.
- **Layout metadata:** track `total_view_lines`/`total_injected_lines` to bound scrolling.
- **Cursor movement helpers:** use `layout_nav` on view positions instead of byte→view mapping.

## navigation/action_convert.rs
- **Purpose:** Full action coverage in view space.
- **Tasks:**
  - Implement all remaining `Action` variants (word moves/select, block/rect selects, mouse, clipboard, undo/redo glue) in view coordinates.
  - Edits: always emit view positions/ranges; attach `source_range` only when both endpoints map to real source bytes via layout.
  - Movements: use `layout_nav` (line/word/page/doc/start/end, block, mouse hit-testing via layout).
- **Notes:** No byte fallbacks; view-only lines produce view-only events.

## actions.rs
- Remove or re-export the new converter; no byte-based pipeline remains.

## state.rs tests/helpers
- Update tests to construct events with `ViewEventPosition/Range`; expectations in view coords.
- Rewrite or drop helpers that assume byte positions; source-aware assertions should use layout mappings explicitly.

## Plugins / LSP glue
- `event_hooks.rs` / `plugin_thread.rs` / `ts_runtime.rs` already view-based; align LSP change path in `render.rs` with view-centric events (only emit LSP edits when `source_range` exists).

---

Execution order suggestion: position_history → word_navigation (view helpers) → viewport → split_rendering + status_bar → navigation/action_convert completion → editor/input → editor/render → tests/helpers cleanup.
