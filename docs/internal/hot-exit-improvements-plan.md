# Hot Exit Improvements: Behavioral PRD & Implementation Plan

This document covers the design and implementation plan for addressing issues
#1231, #1232, #1233, #1234, #1237 (and umbrella #1238). Issues #1235 (detach
vs quit) and #1236 (implicit sessions) are explicitly deferred.

---

## 1. Behavioral PRD

### 1.1 Design Principles

1. **Never silently discard unsaved data.** Unsaved buffers must only disappear
   through explicit user action (closing a tab with confirmation). Every other
   path — exit, reopen, session switch, CLI invocation — must preserve them.

2. **Restore exactly what was there.** On relaunch, the user should see the
   same tabs in the same order with the same active buffer. No extra buffers
   injected, no buffers missing, no reordering.

3. **CLI files are additive.** Specifying file arguments on the command line
   adds those files to the restored workspace; it never replaces it.

4. **Session isolation.** Each named session has its own recovery data. One
   session's exit must never clobber another session's unsaved state.

5. **Inform, don't surprise.** When state is restored, tell the user. When
   recovery is skipped (e.g., file changed on disk), tell the user.

### 1.2 UX Flows

#### Flow A: Launch with no arguments, no session

```
User runs: fresh
            ↓
    ┌─ Workspace file exists for CWD?
    │   YES → Restore workspace (tabs, order, splits, cursors, scroll)
    │         → Apply hot exit recovery to restored buffers
    │         → Apply hot exit recovery for unnamed buffers
    │         → Show status: "Restored N buffer(s) from previous session"
    │         → Active buffer = whatever was active when workspace was saved
    │         → Do NOT create extra unnamed buffer
    │
    │   NO  → Has recovery files (crash recovery)?
    │         YES → recover_all_buffers() (existing crash path)
    │         NO  → Create single unnamed buffer (default)
    └─
```

**Change from current behavior**: When workspace restore succeeds and there are
no CLI files, the editor no longer creates an extra empty unnamed buffer
(fixes #1231).

#### Flow B: Launch with file arguments, no session

```
User runs: fresh file1.txt file2.txt
            ↓
    ┌─ Workspace file exists for CWD?
    │   YES → Restore workspace (all tabs, order, splits, cursors)
    │         → Apply hot exit recovery to all restored buffers
    │         → Then open CLI files:
    │           - If file already open (from workspace), just focus it
    │           - If file is new, append tab at end of active split's tab bar
    │         → Set active buffer = last CLI-specified file
    │         → Show status: "Restored N buffer(s), opened M file(s)"
    │
    │   NO  → Open CLI files in order specified
    │         → Apply hot exit recovery to those files (existing behavior)
    │         → Also recover any non-file-backed (unnamed) buffers from recovery
    │         → Active buffer = last CLI file
    └─
```

**Change from current behavior**: Previously, launching with file arguments
would skip workspace restore entirely, discarding all previously-open tabs.
Now workspace is always restored first, CLI files are layered on top
(fixes #1232).

#### Flow C: Launch with named session, no file arguments

```
User runs: fresh -a mysession
            ↓
    ┌─ Server for 'mysession' already running?
    │   YES → Connect to server (hot exit irrelevant, buffers are live)
    │
    │   NO  → Start new server for 'mysession'
    │         → Look for workspace in session-scoped workspace dir
    │         → Look for recovery data in session-scoped recovery dir
    │         → Restore workspace + apply session-scoped hot exit recovery
    │         → Show status: "Restored session 'mysession' (N buffer(s))"
    └─
```

**Change from current behavior**: Recovery data is now stored per-session
rather than globally. Session 'foo' exiting no longer overwrites session
'bar's recovery files (fixes #1233).

#### Flow D: Launch with named session AND file arguments

```
User runs: fresh -a mysession file.txt
            ↓
    ┌─ Server for 'mysession' already running?
    │   YES → Connect to server
    │         → Send OpenFiles control message for file.txt
    │         → Server opens file.txt (appends to tab bar, focuses it)
    │
    │   NO  → Start new server (same as Flow C)
    │         → Restore workspace + hot exit recovery
    │         → Open file.txt:
    │           - If already in restored tabs, focus it
    │           - Otherwise append to tab bar and focus
    └─
```

**Change from current behavior**: File arguments now work correctly with
session restore rather than replacing the session state (fixes #1237).

#### Flow E: Exit (clean shutdown)

```
User quits (Ctrl+Q or :q)
            ↓
    1. Capture workspace state:
       - Tab order (explicit ordered list, not iteration order)
       - Active tab per split
       - Cursor positions, scroll positions
       - Split layout, file explorer state
       - Unnamed buffer references (recovery IDs)

    2. Save recovery data for dirty buffers:
       - File-backed modified buffers → recovery files
       - Unnamed modified buffers → recovery files
       - Recovery dir = session-scoped if in session mode

    3. Save workspace to:
       - Session-scoped workspace dir if in session mode
       - CWD-scoped workspace dir if in standalone mode

    4. Clean up session lock file
```

**Change from current behavior**: Tab order is now explicitly serialized as
an ordered array rather than relying on HashMap iteration order (fixes #1234).
Recovery files are written to a session-scoped directory when running in
session mode.

#### Flow F: File changed on disk since hot exit

```
During hot exit recovery, for each file-backed buffer:
            ↓
    ┌─ File mtime matches recovery metadata's original_mtime?
    │   YES → Apply recovery (restore unsaved changes)
    │
    │   NO  → Do NOT silently skip
    │         → Open the file with current disk contents
    │         → Show warning in status bar:
    │           "file.txt changed on disk; unsaved changes not restored"
    │         → Keep recovery file (don't delete) for manual inspection
    └─
```

**Change from current behavior**: Currently, when mtime doesn't match, the
recovery is silently skipped and the recovery file is deleted. The user never
knows they had unsaved changes. Now the user is warned and the recovery file
is preserved.

### 1.3 Configuration

The two existing settings `persist_unnamed_buffers` and `hot_exit` are merged
into a single setting:

```toml
[editor]
# Controls whether the editor preserves unsaved state across sessions.
# When enabled, all buffers (file-backed and unnamed) are preserved on exit
# and restored on next launch. No "Save changes?" prompt on clean exit.
#
# Values: true (default), false
hot_exit = true
```

The old `persist_unnamed_buffers` key is accepted as an alias during config
loading for backward compatibility but is not documented.

### 1.4 Status Messages

| Scenario | Message |
|---|---|
| Workspace restored | `"Restored N buffer(s) from previous session"` |
| Session restored | `"Restored session 'name' (N buffer(s))"` |
| Recovery skipped (mtime) | `"file.txt changed on disk; unsaved changes not restored"` |
| Crash recovery | (existing UI — recovery prompt unchanged) |

---

## 2. Architecture Changes

### 2.1 Session-Scoped Recovery Storage

**Current layout:**
```
~/.local/share/fresh/
├── recovery/           ← global, shared by all instances
│   ├── session.lock
│   ├── {id}.meta.json
│   └── {id}.chunk.N
└── workspaces/         ← already CWD-scoped
    └── {encoded_cwd}.json
```

**New layout:**
```
~/.local/share/fresh/
├── recovery/
│   ├── default/        ← standalone mode (no -a), scoped by CWD hash
│   │   ├── {cwd_hash}/
│   │   │   ├── session.lock
│   │   │   ├── {id}.meta.json
│   │   │   └── {id}.chunk.N
│   │   └── ...
│   └── sessions/       ← session mode (-a NAME)
│       ├── {session_name}/
│       │   ├── session.lock
│       │   ├── {id}.meta.json
│       │   └── {id}.chunk.N
│       └── ...
├── workspaces/         ← standalone mode (unchanged, CWD-scoped)
│   └── {encoded_cwd}.json
└── session-workspaces/ ← session mode workspace files
    └── {session_name}.json
```

**Migration**: On startup, if old-style recovery files exist in `recovery/`
(flat layout with no `default/` or `sessions/` subdirs), migrate them into
`recovery/default/{cwd_hash}/` based on the current working directory. This
is a one-time migration.

### 2.2 RecoveryStorage Scoping

`RecoveryStorage::new()` currently always points to `~/.local/share/fresh/recovery/`.
We add a constructor that accepts a scope:

```rust
pub enum RecoveryScope {
    /// Standalone mode: scoped by working directory
    Standalone { working_dir: PathBuf },
    /// Session mode: scoped by session name
    Session { name: String },
}

impl RecoveryStorage {
    pub fn with_scope(scope: RecoveryScope) -> io::Result<Self> { ... }
}
```

### 2.3 Workspace Storage for Sessions

`Workspace::load()` and `Workspace::save()` currently use
`get_workspace_path(working_dir)`. For session mode, we add:

```rust
pub fn get_session_workspace_path(session_name: &str) -> io::Result<PathBuf> {
    let dir = get_data_dir()?.join("session-workspaces");
    fs::create_dir_all(&dir)?;
    Ok(dir.join(format!("{}.json", session_name)))
}
```

And `Workspace` gets `load_session(name)` / `save_session(name)` methods.

### 2.4 Tab Order Serialization Fix

`SerializedSplitViewState.open_tabs` already exists as `Vec<SerializedTabRef>`,
which is an ordered list. The bug is in `capture_workspace()` where the tab
list is built. Need to verify that `serialize_split_view_state()` preserves
the visual tab order from the split manager rather than iterating a HashMap.

---

## 3. Implementation Plan

### Phase 1: Bug Fixes (no architectural changes)

#### Task 1.1: Fix extra unnamed buffer on restore (#1231)

**Files**: `main.rs` (`handle_first_run_setup`)

**Problem**: When workspace restore succeeds AND no CLI files are given, an
empty unnamed buffer (BufferId 1) is left open alongside the restored tabs.

**Fix**: After `try_restore_workspace()` succeeds, check if the initial
unnamed buffer (BufferId 1) is still empty/unmodified/unnamed. If so, close
it and remove it from the tab bar. This is the same pattern used by
`open_stdin_buffer()` which replaces the initial buffer when stdin is piped.

Specifically, in `apply_workspace()` (workspace.rs), after files are opened
and tabs rebuilt, check if BufferId 1 is in the tab bar and is
empty/unmodified/unnamed. If the workspace had any files to restore, remove
BufferId 1 from the split's open_tabs.

#### Task 1.2: Fix buffer ordering on restore (#1234)

**Files**: `workspace.rs` (`capture_workspace`, `apply_workspace`)

**Problem**: Buffer order after hot exit appears random.

**Investigation**: Verify that `capture_workspace()` serializes
`open_tabs` in visual tab-bar order. The `split_manager` should provide tabs
in order. If it does, the bug might be in `apply_workspace()` where files are
opened — opening files via `open_file_internal()` may append them in arbitrary
order and then tab reordering doesn't happen.

**Fix**: In `apply_workspace()`, after opening all files, explicitly set the
tab order for each split to match the serialized `open_tabs` order. The
`SplitViewState` should have a method to reorder tabs to match a given
sequence of BufferIds.

#### Task 1.3: Don't discard hot exit recovery when CLI files specified (#1232)

**Files**: `main.rs` (`handle_first_run_setup`)

**Problem**: `fresh file.txt` discards all previously-open buffers from the
workspace.

**Current flow**:
1. `try_restore_workspace()` is called (may restore workspace)
2. CLI files are queued
3. `recover_all_buffers()` runs for crash recovery only

**Fix**: The workspace restore already happens before CLI files are queued
(line 746). The issue is that workspace restore might not be happening, OR
the workspace is restored but then the initial unnamed buffer crowds the
tab bar. Ensure:
1. `try_restore_workspace()` always runs (currently it does)
2. CLI files are opened AFTER workspace restore, appended to tab bar
3. Active buffer is set to the last CLI file
4. The initial empty unnamed buffer is cleaned up (same as Task 1.1)

Also: `recover_all_buffers()` (the crash-recovery path at line 793) currently
opens NEW buffers for recovered files, even if those files weren't in the
workspace. This is correct for crash recovery but creates duplicates if the
workspace also had those files. Need to deduplicate: if a recovered file is
already open (from workspace restore), apply recovery content to the existing
buffer instead of opening a new one.

### Phase 2: Session-Scoped Recovery (#1233)

#### Task 2.1: Add RecoveryScope and scoped storage

**Files**: `services/recovery/storage.rs`, `services/recovery/mod.rs`

Add `RecoveryScope` enum. Modify `RecoveryStorage::new()` to accept an
optional scope. The recovery directory becomes:
- Standalone: `recovery/default/{cwd_hash}/`
- Session: `recovery/sessions/{session_name}/`

Add migration logic: if `recovery/session.lock` exists at the old flat path,
move all files into `recovery/default/{current_cwd_hash}/`.

#### Task 2.2: Pass session context through to RecoveryStorage

**Files**: `app/mod.rs` (Editor constructor), `server/editor_server.rs`,
`main.rs`

The Editor needs to know its recovery scope at construction time. Add a
`recovery_scope: Option<RecoveryScope>` to `EditorOptions` or pass it to
`Editor::with_working_dir()`. In session mode (`editor_server.rs`), set
`RecoveryScope::Session { name }`. In standalone mode, set
`RecoveryScope::Standalone { working_dir }`.

#### Task 2.3: Session-scoped workspace files

**Files**: `workspace.rs`

Add `get_session_workspace_path(session_name)`. In session mode, workspace
save/load uses session name instead of CWD. This means a session always
restores ITS workspace regardless of which directory the client connects from.

Add `Workspace::load_session()` and `Workspace::save_session()` methods,
or parameterize existing `load()`/`save()` with an enum.

#### Task 2.4: Wire session name through server lifecycle

**Files**: `server/editor_server.rs`, `server/daemon/unix.rs`, `main.rs`

Ensure the session name is available to the Editor when running in server
mode. Currently `spawn_server_detached()` passes `--session-name NAME`. The
server startup path should forward this name to the Editor so it can
construct the correct `RecoveryScope`.

### Phase 3: CLI Files + Session Restore (#1237)

#### Task 3.1: Open CLI files within an existing session server

**Files**: `server/editor_server.rs`, `server/protocol.rs`

When `fresh -a mysession file.txt` connects to an ALREADY RUNNING server,
it sends `ClientControl::OpenFiles`. Verify this works correctly — the server
should open the file and focus it. This likely already works but needs testing.

#### Task 3.2: Open CLI files in a freshly-started session

**Files**: `main.rs`, `server/editor_server.rs`

When `fresh -a mysession file.txt` starts a NEW server, the file arguments
need to be forwarded. Currently `spawn_server_detached()` doesn't forward
file arguments to the server process. The client connects and then sends
`OpenFiles` via the control socket.

Verify this path works with workspace restore: the server should restore the
session workspace, THEN process the `OpenFiles` message from the client.
The file should be appended to the tab bar and focused. If the file is
already in the restored workspace, it should just be focused (not duplicated).

### Phase 4: Notifications and Polish

#### Task 4.1: Status bar notification on restore

**Files**: `app/workspace.rs`, `app/mod.rs`

After workspace restore + hot exit recovery completes, set a status message
visible to the user. Use the existing status bar message mechanism
(`set_status_message()`).

#### Task 4.2: Warn when recovery skipped due to mtime mismatch

**Files**: `app/recovery_actions.rs`, `app/workspace.rs`

In `recover_all_buffers()` and `apply_hot_exit_recovery()`, when
`RecoveryResult::OriginalFileModified` is returned, instead of silently
discarding the recovery file:
1. Show a status warning
2. Keep the recovery file on disk (don't call `discard_recovery()`)

Add a method to list preserved-but-skipped recovery files so users can
manually inspect them later.

#### Task 4.3: Merge config settings

**Files**: `config.rs`, `app/recovery_actions.rs`, `app/workspace.rs`,
`app/prompt_actions.rs`

1. In config loading, treat `persist_unnamed_buffers` as an alias for
   `hot_exit` (for backward compatibility).
2. Remove all internal branching that checks them separately — use a single
   `hot_exit` flag.
3. Update config documentation / settings UI.

### Phase 5: Testing

#### Task 5.1: Integration tests for each flow

Add or extend integration tests for:
- Workspace restore without CLI files → no extra unnamed buffer
- Workspace restore with CLI files → workspace + CLI files, CLI focused
- Tab order preserved across save/restore cycle
- Session-scoped recovery isolation (two sessions, each with own dirty buffers)
- File mtime change → warning, recovery not deleted
- `fresh -a session file.txt` → file opened in restored session

#### Task 5.2: Migration test

Test that existing flat-layout recovery files are correctly migrated into
the new scoped directory structure on first launch.

---

## 4. Risk Assessment

| Risk | Mitigation |
|---|---|
| Migration corrupts existing recovery files | Migrate by copying, not moving. Only delete originals after confirming copies are readable. |
| Tab order fix regresses other tab behaviors | Existing test suite + new order-specific tests |
| Config merge breaks users who set them independently | `persist_unnamed_buffers` accepted as alias; both `true` = `hot_exit: true` |
| Session workspace path collisions | Session names are user-chosen strings; sanitize for filesystem safety |
| Race between client OpenFiles and server workspace restore | Server should fully complete startup/restore before accepting client connections (already the case — server binds sockets after init) |
