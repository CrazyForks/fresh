//! Active authority abstraction.
//!
//! An `ActiveAuthority` bundles the filesystem, process spawner, terminal
//! wrapping, and display-string surface that describes where the editor is
//! operating. Today the variants are constructed directly from
//! `initialize_app` (local, SSH, devcontainer). A future plugin op
//! (`editor.registerAuthorityProvider`) will let plugins supply providers.
//!
//! This is step 3 of `docs/internal/DEVCONTAINER_INTEGRATION_PLAN.md`.

use std::sync::Arc;

use crate::model::filesystem::FileSystem;
use crate::services::remote::ProcessSpawner;

/// How an integrated terminal is spawned under this authority.
///
/// When `Some`, the `TerminalManager` replaces the local shell command with
/// `command` + `args` instead of calling `detect_shell()`. Intended for
/// authorities that re-parent terminals into a container, remote shell,
/// nix shell, etc.
#[derive(Debug, Clone)]
pub struct TerminalWrapper {
    /// Command to execute instead of the host shell (e.g. `"docker"`).
    pub command: String,
    /// Arguments that make the command drop the user into an interactive
    /// shell in the right context (e.g.
    /// `["exec", "-it", "-u", "vscode", "-w", "/workspaces/proj", "<id>", "bash", "-l"]`).
    pub args: Vec<String>,
    /// If true, the inner cwd is already handled by `args` (e.g. via
    /// `docker exec -w`) and the `TerminalManager` must not call
    /// `CommandBuilder::cwd()`. For host shells this is false.
    pub manages_cwd: bool,
}

/// Everything the editor needs to know about the environment it is attached
/// to. Exactly one is active per workspace.
#[derive(Clone)]
pub struct ActiveAuthority {
    pub filesystem: Arc<dyn FileSystem + Send + Sync>,
    pub process_spawner: Arc<dyn ProcessSpawner>,
    /// Optional wrapper for integrated terminal spawns. `None` means spawn
    /// the host shell directly.
    pub terminal_wrapper: Option<TerminalWrapper>,
    /// Text shown in the status bar and file explorer header
    /// (e.g. `"user@host"`, `"Container:abc123"`). `None` means local.
    pub display_string: Option<String>,
}

impl ActiveAuthority {
    /// Default local authority: host filesystem, host process spawner, no
    /// terminal wrapper, no display string.
    pub fn local() -> Self {
        Self {
            filesystem: Arc::new(crate::model::filesystem::StdFileSystem),
            process_spawner: Arc::new(crate::services::remote::LocalProcessSpawner),
            terminal_wrapper: None,
            display_string: None,
        }
    }
}
