#!/usr/bin/env bash
#
# Source Code Reorganization Script
#
# This script implements the reorganization plan from docs/ORGANIZE.md
# It moves files to their new locations and updates import paths.
#
# Usage:
#   ./scripts/reorganize.sh [phase]
#
# Phases:
#   1 - Create directories
#   2 - Move model files
#   3 - Move editor -> app
#   4 - Move input files
#   5 - Move view files
#   6 - Move services files
#   7 - Move primitives files
#   all - Run all phases (default)
#   dry-run - Show what would be done without making changes
#
# After running, you'll need to:
#   1. Run 'cargo build' to check for errors
#   2. Fix any remaining import issues
#   3. Commit the changes
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=false

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Git mv wrapper that respects dry-run
git_mv() {
    local src="$1"
    local dst="$2"
    if [ "$DRY_RUN" = true ]; then
        echo "  Would move: $src -> $dst"
    else
        if [ -e "$src" ]; then
            mkdir -p "$(dirname "$dst")"
            git mv "$src" "$dst"
            log_success "Moved: $src -> $dst"
        else
            log_warn "Source not found: $src"
        fi
    fi
}

# Create directory wrapper
create_dir() {
    local dir="$1"
    if [ "$DRY_RUN" = true ]; then
        echo "  Would create: $dir"
    else
        mkdir -p "$dir"
        log_success "Created: $dir"
    fi
}

# Write file wrapper
write_file() {
    local file="$1"
    local content="$2"
    if [ "$DRY_RUN" = true ]; then
        echo "  Would write: $file"
    else
        echo "$content" > "$file"
        git add "$file"
        log_success "Written: $file"
    fi
}

# Update imports in all Rust files
update_imports() {
    local old_path="$1"
    local new_path="$2"

    if [ "$DRY_RUN" = true ]; then
        echo "  Would replace: crate::$old_path -> crate::$new_path"
        return
    fi

    # Use find + sed to update imports
    # Handle both 'use crate::' and 'crate::' references
    find "$SRC_DIR" -name "*.rs" -type f -exec sed -i \
        -e "s/crate::${old_path}::/crate::${new_path}::/g" \
        -e "s/use crate::${old_path};/use crate::${new_path};/g" \
        -e "s/use crate::${old_path} /use crate::${new_path} /g" \
        {} +

    log_success "Updated imports: $old_path -> $new_path"
}

# Phase 1: Create directories
phase1_create_dirs() {
    log_info "Phase 1: Creating directories..."

    create_dir "$SRC_DIR/app"
    create_dir "$SRC_DIR/model"
    create_dir "$SRC_DIR/view"
    create_dir "$SRC_DIR/input"
    create_dir "$SRC_DIR/services"
    create_dir "$SRC_DIR/services/lsp"
    create_dir "$SRC_DIR/services/plugins"
    create_dir "$SRC_DIR/primitives"

    log_success "Phase 1 complete!"
}

# Phase 2: Move model files
phase2_model() {
    log_info "Phase 2: Moving model files..."

    git_mv "$SRC_DIR/text_buffer.rs" "$SRC_DIR/model/buffer.rs"
    git_mv "$SRC_DIR/piece_tree.rs" "$SRC_DIR/model/piece_tree.rs"
    git_mv "$SRC_DIR/cursor.rs" "$SRC_DIR/model/cursor.rs"
    git_mv "$SRC_DIR/marker.rs" "$SRC_DIR/model/marker.rs"
    git_mv "$SRC_DIR/marker_tree.rs" "$SRC_DIR/model/marker_tree.rs"
    git_mv "$SRC_DIR/event.rs" "$SRC_DIR/model/event.rs"
    git_mv "$SRC_DIR/edit.rs" "$SRC_DIR/model/edit.rs"
    git_mv "$SRC_DIR/control_event.rs" "$SRC_DIR/model/control_event.rs"
    git_mv "$SRC_DIR/document_model.rs" "$SRC_DIR/model/document_model.rs"

    # Create mod.rs for model
    local model_mod='//! Core data model for documents
//!
//! This module contains pure data structures with minimal external dependencies.

pub mod buffer;
pub mod piece_tree;
pub mod cursor;
pub mod marker;
pub mod marker_tree;
pub mod event;
pub mod edit;
pub mod control_event;
pub mod document_model;

// Re-exports for convenience
pub use buffer::TextBuffer;
pub use cursor::{Cursor, Selection};
pub use event::{Event, BufferId, CursorId, SplitId};
pub use piece_tree::PieceTree;
pub use marker::{Marker, MarkerHandle};
pub use marker_tree::MarkerTree;
pub use edit::{Edit, EditKind};
pub use control_event::{ControlEvent, EventBroadcaster};
pub use document_model::DocumentModel;'

    write_file "$SRC_DIR/model/mod.rs" "$model_mod"

    # Update imports
    update_imports "text_buffer" "model::buffer"
    update_imports "piece_tree" "model::piece_tree"
    update_imports "cursor" "model::cursor"
    update_imports "marker_tree" "model::marker_tree"
    update_imports "marker" "model::marker"
    update_imports "event" "model::event"
    update_imports "edit" "model::edit"
    update_imports "control_event" "model::control_event"
    update_imports "document_model" "model::document_model"

    log_success "Phase 2 complete!"
}

# Phase 3: Move editor -> app
phase3_app() {
    log_info "Phase 3: Moving editor to app..."

    # Move the entire editor directory contents
    git_mv "$SRC_DIR/editor/mod.rs" "$SRC_DIR/app/mod.rs"
    git_mv "$SRC_DIR/editor/input.rs" "$SRC_DIR/app/input.rs"
    git_mv "$SRC_DIR/editor/render.rs" "$SRC_DIR/app/render.rs"
    git_mv "$SRC_DIR/editor/file_explorer.rs" "$SRC_DIR/app/file_explorer.rs"
    git_mv "$SRC_DIR/editor/types.rs" "$SRC_DIR/app/types.rs"

    # Move script_control.rs into app
    git_mv "$SRC_DIR/script_control.rs" "$SRC_DIR/app/script_control.rs"

    # Remove empty editor directory
    if [ "$DRY_RUN" = false ] && [ -d "$SRC_DIR/editor" ]; then
        rmdir "$SRC_DIR/editor" 2>/dev/null || true
    fi

    # Update imports
    update_imports "editor" "app"
    update_imports "script_control" "app::script_control"

    log_success "Phase 3 complete!"
}

# Phase 4: Move input files
phase4_input() {
    log_info "Phase 4: Moving input files..."

    git_mv "$SRC_DIR/actions.rs" "$SRC_DIR/input/actions.rs"
    git_mv "$SRC_DIR/commands.rs" "$SRC_DIR/input/commands.rs"
    git_mv "$SRC_DIR/keybindings.rs" "$SRC_DIR/input/keybindings.rs"
    git_mv "$SRC_DIR/command_registry.rs" "$SRC_DIR/input/command_registry.rs"
    git_mv "$SRC_DIR/input_history.rs" "$SRC_DIR/input/input_history.rs"
    git_mv "$SRC_DIR/position_history.rs" "$SRC_DIR/input/position_history.rs"
    git_mv "$SRC_DIR/buffer_mode.rs" "$SRC_DIR/input/buffer_mode.rs"
    git_mv "$SRC_DIR/multi_cursor.rs" "$SRC_DIR/input/multi_cursor.rs"

    # Create mod.rs for input
    local input_mod='//! Input pipeline
//!
//! This module handles the input-to-action-to-event translation.

pub mod actions;
pub mod commands;
pub mod keybindings;
pub mod command_registry;
pub mod input_history;
pub mod position_history;
pub mod buffer_mode;
pub mod multi_cursor;

// Re-exports
pub use actions::Action;
pub use commands::Command;
pub use keybindings::{KeyBinding, Keybindings};
pub use command_registry::CommandRegistry;
pub use input_history::InputHistory;
pub use position_history::PositionHistory;
pub use buffer_mode::BufferMode;
pub use multi_cursor::MultiCursor;'

    write_file "$SRC_DIR/input/mod.rs" "$input_mod"

    # Update imports
    update_imports "actions" "input::actions"
    update_imports "commands" "input::commands"
    update_imports "keybindings" "input::keybindings"
    update_imports "command_registry" "input::command_registry"
    update_imports "input_history" "input::input_history"
    update_imports "position_history" "input::position_history"
    update_imports "buffer_mode" "input::buffer_mode"
    update_imports "multi_cursor" "input::multi_cursor"

    log_success "Phase 4 complete!"
}

# Phase 5: Move view files
phase5_view() {
    log_info "Phase 5: Moving view files..."

    # Move individual view files
    git_mv "$SRC_DIR/split.rs" "$SRC_DIR/view/split.rs"
    git_mv "$SRC_DIR/viewport.rs" "$SRC_DIR/view/viewport.rs"
    git_mv "$SRC_DIR/popup.rs" "$SRC_DIR/view/popup.rs"
    git_mv "$SRC_DIR/prompt.rs" "$SRC_DIR/view/prompt.rs"
    git_mv "$SRC_DIR/overlay.rs" "$SRC_DIR/view/overlay.rs"
    git_mv "$SRC_DIR/virtual_text.rs" "$SRC_DIR/view/virtual_text.rs"
    git_mv "$SRC_DIR/margin.rs" "$SRC_DIR/view/margin.rs"
    git_mv "$SRC_DIR/theme.rs" "$SRC_DIR/view/theme.rs"
    git_mv "$SRC_DIR/view.rs" "$SRC_DIR/view/stream.rs"

    # Move ui directory
    git_mv "$SRC_DIR/ui" "$SRC_DIR/view/ui"

    # Move file_tree directory
    git_mv "$SRC_DIR/file_tree" "$SRC_DIR/view/file_tree"

    # Create mod.rs for view
    local view_mod='//! View and UI layer
//!
//! This module contains all presentation and rendering components.

pub mod split;
pub mod viewport;
pub mod popup;
pub mod prompt;
pub mod overlay;
pub mod virtual_text;
pub mod margin;
pub mod theme;
pub mod stream;
pub mod ui;
pub mod file_tree;

// Re-exports
pub use split::{Split, SplitDirection};
pub use viewport::Viewport;
pub use popup::Popup;
pub use prompt::Prompt;
pub use overlay::{Overlay, OverlayHandle, OverlayFace};
pub use virtual_text::{VirtualText, VirtualTextPosition};
pub use margin::Margin;
pub use theme::Theme;
pub use stream::{ViewStream, ViewToken};'

    write_file "$SRC_DIR/view/mod.rs" "$view_mod"

    # Update imports
    update_imports "split" "view::split"
    update_imports "viewport" "view::viewport"
    update_imports "popup" "view::popup"
    update_imports "prompt" "view::prompt"
    update_imports "overlay" "view::overlay"
    update_imports "virtual_text" "view::virtual_text"
    update_imports "margin" "view::margin"
    update_imports "theme" "view::theme"
    update_imports "view::" "view::stream::"
    update_imports "ui::" "view::ui::"
    update_imports "file_tree" "view::file_tree"

    log_success "Phase 5 complete!"
}

# Phase 6: Move services files
phase6_services() {
    log_info "Phase 6: Moving services files..."

    # Move LSP files
    git_mv "$SRC_DIR/lsp_manager.rs" "$SRC_DIR/services/lsp/manager.rs"
    git_mv "$SRC_DIR/lsp.rs" "$SRC_DIR/services/lsp/client.rs"
    git_mv "$SRC_DIR/lsp_async.rs" "$SRC_DIR/services/lsp/async_handler.rs"
    git_mv "$SRC_DIR/lsp_diagnostics.rs" "$SRC_DIR/services/lsp/diagnostics.rs"

    # Create LSP mod.rs
    local lsp_mod='//! LSP (Language Server Protocol) integration

pub mod manager;
pub mod client;
pub mod async_handler;
pub mod diagnostics;

pub use manager::LspManager;
pub use client::LspClient;
pub use diagnostics::DiagnosticsManager;'

    write_file "$SRC_DIR/services/lsp/mod.rs" "$lsp_mod"

    # Move plugin files
    git_mv "$SRC_DIR/plugin_thread.rs" "$SRC_DIR/services/plugins/thread.rs"
    git_mv "$SRC_DIR/plugin_api.rs" "$SRC_DIR/services/plugins/api.rs"
    git_mv "$SRC_DIR/plugin_process.rs" "$SRC_DIR/services/plugins/process.rs"
    git_mv "$SRC_DIR/ts_runtime.rs" "$SRC_DIR/services/plugins/runtime.rs"
    git_mv "$SRC_DIR/hooks.rs" "$SRC_DIR/services/plugins/hooks.rs"
    git_mv "$SRC_DIR/event_hooks.rs" "$SRC_DIR/services/plugins/event_hooks.rs"

    # Create plugins mod.rs
    local plugins_mod='//! Plugin system

pub mod thread;
pub mod api;
pub mod process;
pub mod runtime;
pub mod hooks;
pub mod event_hooks;

pub use thread::PluginThread;
pub use api::PluginApi;
pub use process::PluginProcess;
pub use hooks::{HookRegistry, HookArgs};
pub use event_hooks::EventHooks;'

    write_file "$SRC_DIR/services/plugins/mod.rs" "$plugins_mod"

    # Move other service files
    git_mv "$SRC_DIR/fs" "$SRC_DIR/services/fs"
    git_mv "$SRC_DIR/async_bridge.rs" "$SRC_DIR/services/async_bridge.rs"
    git_mv "$SRC_DIR/clipboard.rs" "$SRC_DIR/services/clipboard.rs"
    git_mv "$SRC_DIR/signal_handler.rs" "$SRC_DIR/services/signal_handler.rs"
    git_mv "$SRC_DIR/process_limits.rs" "$SRC_DIR/services/process_limits.rs"

    # Create services mod.rs
    local services_mod='//! Asynchronous services and external integrations
//!
//! This module contains all code that deals with external processes,
//! I/O, and async operations.

pub mod lsp;
pub mod plugins;
pub mod fs;
pub mod async_bridge;
pub mod clipboard;
pub mod signal_handler;
pub mod process_limits;

// Re-exports
pub use async_bridge::AsyncBridge;
pub use clipboard::Clipboard;
pub use signal_handler::SignalHandler;
pub use process_limits::ProcessLimits;'

    write_file "$SRC_DIR/services/mod.rs" "$services_mod"

    # Update imports
    update_imports "lsp_manager" "services::lsp::manager"
    update_imports "lsp::" "services::lsp::client::"
    update_imports "lsp_async" "services::lsp::async_handler"
    update_imports "lsp_diagnostics" "services::lsp::diagnostics"
    update_imports "plugin_thread" "services::plugins::thread"
    update_imports "plugin_api" "services::plugins::api"
    update_imports "plugin_process" "services::plugins::process"
    update_imports "ts_runtime" "services::plugins::runtime"
    update_imports "hooks" "services::plugins::hooks"
    update_imports "event_hooks" "services::plugins::event_hooks"
    update_imports "fs::" "services::fs::"
    update_imports "async_bridge" "services::async_bridge"
    update_imports "clipboard" "services::clipboard"
    update_imports "signal_handler" "services::signal_handler"
    update_imports "process_limits" "services::process_limits"

    log_success "Phase 6 complete!"
}

# Phase 7: Move primitives files
phase7_primitives() {
    log_info "Phase 7: Moving primitives files..."

    git_mv "$SRC_DIR/highlighter.rs" "$SRC_DIR/primitives/highlighter.rs"
    git_mv "$SRC_DIR/semantic_highlight.rs" "$SRC_DIR/primitives/semantic_highlight.rs"
    git_mv "$SRC_DIR/ansi.rs" "$SRC_DIR/primitives/ansi.rs"
    git_mv "$SRC_DIR/ansi_background.rs" "$SRC_DIR/primitives/ansi_background.rs"
    git_mv "$SRC_DIR/indent.rs" "$SRC_DIR/primitives/indent.rs"
    git_mv "$SRC_DIR/text_property.rs" "$SRC_DIR/primitives/text_property.rs"
    git_mv "$SRC_DIR/word_navigation.rs" "$SRC_DIR/primitives/word_navigation.rs"
    git_mv "$SRC_DIR/line_wrapping.rs" "$SRC_DIR/primitives/line_wrapping.rs"
    git_mv "$SRC_DIR/line_iterator.rs" "$SRC_DIR/primitives/line_iterator.rs"

    # Create mod.rs for primitives
    local primitives_mod='//! Low-level primitives and utilities
//!
//! This module contains syntax highlighting, ANSI handling,
//! and text manipulation utilities.

pub mod highlighter;
pub mod semantic_highlight;
pub mod ansi;
pub mod ansi_background;
pub mod indent;
pub mod text_property;
pub mod word_navigation;
pub mod line_wrapping;
pub mod line_iterator;

// Re-exports
pub use highlighter::Highlighter;
pub use semantic_highlight::SemanticHighlighter;
pub use ansi::{AnsiStyle, AnsiParser};
pub use indent::IndentDetector;
pub use text_property::TextProperty;
pub use word_navigation::WordNavigation;
pub use line_wrapping::LineWrapper;
pub use line_iterator::LineIterator;'

    write_file "$SRC_DIR/primitives/mod.rs" "$primitives_mod"

    # Update imports
    update_imports "highlighter" "primitives::highlighter"
    update_imports "semantic_highlight" "primitives::semantic_highlight"
    update_imports "ansi::" "primitives::ansi::"
    update_imports "ansi_background" "primitives::ansi_background"
    update_imports "indent" "primitives::indent"
    update_imports "text_property" "primitives::text_property"
    update_imports "word_navigation" "primitives::word_navigation"
    update_imports "line_wrapping" "primitives::line_wrapping"
    update_imports "line_iterator" "primitives::line_iterator"

    log_success "Phase 7 complete!"
}

# Update lib.rs to reflect new structure
update_lib_rs() {
    log_info "Updating lib.rs..."

    if [ "$DRY_RUN" = true ]; then
        echo "  Would update lib.rs with new module structure"
        return
    fi

    local lib_content='// Editor library - exposes all core modules for testing

// Core modules at root level
pub mod config;
pub mod state;

// Organized modules
pub mod app;
pub mod model;
pub mod view;
pub mod input;
pub mod services;
pub mod primitives;
'

    echo "$lib_content" > "$SRC_DIR/lib.rs"
    git add "$SRC_DIR/lib.rs"

    log_success "lib.rs updated!"
}

# Main entry point
main() {
    local phase="${1:-all}"

    cd "$PROJECT_ROOT"

    if [ "$phase" = "dry-run" ]; then
        DRY_RUN=true
        phase="all"
        log_warn "DRY RUN MODE - No changes will be made"
    fi

    echo ""
    echo "================================================"
    echo "  Source Code Reorganization Script"
    echo "  Project: $PROJECT_ROOT"
    echo "  Phase: $phase"
    echo "================================================"
    echo ""

    case "$phase" in
        1)
            phase1_create_dirs
            ;;
        2)
            phase2_model
            ;;
        3)
            phase3_app
            ;;
        4)
            phase4_input
            ;;
        5)
            phase5_view
            ;;
        6)
            phase6_services
            ;;
        7)
            phase7_primitives
            ;;
        all)
            phase1_create_dirs
            phase2_model
            phase3_app
            phase4_input
            phase5_view
            phase6_services
            phase7_primitives
            update_lib_rs
            ;;
        *)
            log_error "Unknown phase: $phase"
            echo "Usage: $0 [1|2|3|4|5|6|7|all|dry-run]"
            exit 1
            ;;
    esac

    echo ""
    log_success "Reorganization phase(s) complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'cargo build' to check for errors"
    echo "  2. Fix any remaining import issues manually"
    echo "  3. Run 'cargo test' to verify functionality"
    echo "  4. Commit changes: git commit -m 'Reorganize source code structure'"
    echo ""
}

main "$@"
