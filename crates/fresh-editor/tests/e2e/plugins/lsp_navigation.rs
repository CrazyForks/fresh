//! E2E tests for lsp_navigation plugin

use crate::common::harness::{copy_plugin, copy_plugin_lib, EditorTestHarness};
use crossterm::event::{KeyCode, KeyModifiers};
use std::fs;

/// Test LSP navigation preview split
///
/// Verifies that the lsp_navigation plugin shows LSP symbols in a finder
/// with a preview split that highlights the selected symbol's range using
/// ">" markers on match lines.
#[test]
#[cfg_attr(windows, ignore)]
fn test_lsp_navigation_preview_split() -> anyhow::Result<()> {
    let temp_dir = tempfile::TempDir::new()?;
    let project_root = temp_dir.path().to_path_buf();

    let plugins_dir = project_root.join("plugins");
    fs::create_dir(&plugins_dir)?;

    copy_plugin(&plugins_dir, "lsp_navigation");
    copy_plugin_lib(&plugins_dir);

    let fake_lsp_script = r#"#!/bin/bash
read_message() {
    local content_length=0
    while IFS=: read -r key value; do
        key=$(echo "$key" | tr -d '\r\n')
        value=$(echo "$value" | tr -d '\r\n ')
        if [ "$key" = "Content-Length" ]; then
            content_length=$value
        fi
        if [ -z "$key" ]; then
            break
        fi
    done
    if [ $content_length -gt 0 ]; then
        dd bs=1 count=$content_length 2>/dev/null
    fi
}
send_message() {
    local message="$1"
    local length=${#message}
    echo -en "Content-Length: $length\r\n\r\n$message"
}
while true; do
    msg=$(read_message)
    if [ -z "$msg" ]; then
        break
    fi
    method=$(echo "$msg" | grep -o '"method":"[^"]*"' | cut -d'"' -f4)
    msg_id=$(echo "$msg" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    case "$method" in
        "initialize")
            send_message '{"jsonrpc":"2.0","id":'$msg_id',"result":{"capabilities":{"documentSymbolProvider":true,"textDocumentSync":1}}}'
            ;;
        "initialized")
            ;;
        "textDocument/didOpen"|"textDocument/didChange"|"textDocument/didSave")
            ;;
        "textDocument/documentSymbol")
            send_message '{"jsonrpc":"2.0","id":'$msg_id',"result":[{"name":"MyClass","kind":5,"location":{"uri":"file://test.ts","range":{"start":{"line":0,"character":0},"end":{"line":8,"character":1}}}},{"name":"constructor","kind":9,"location":{"uri":"file://test.ts","range":{"start":{"line":1,"character":2},"end":{"line":3,"character":3}}}},{"name":"myMethod","kind":6,"location":{"uri":"file://test.ts","range":{"start":{"line":5,"character":2},"end":{"line":7,"character":3}}}}]}'
            ;;
        "shutdown")
            send_message '{"jsonrpc":"2.0","id":'$msg_id',"result":null}'
            break
            ;;
    esac
done
"#;

    let script_path = project_root.join("fake_lsp.sh");
    fs::write(&script_path, fake_lsp_script)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&script_path)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&script_path, perms)?;
    }

    let test_file = project_root.join("test.ts");
    fs::write(
        &test_file,
        r#"class MyClass {
  constructor() {
    return true;
  }

  myMethod(a: number): number {
    return a;
  }
}
"#,
    )?;

    let mut config = fresh::config::Config::default();
    config.lsp.insert(
        "typescript".to_string(),
        fresh::types::LspLanguageConfig::Multi(vec![fresh::services::lsp::LspServerConfig {
            command: script_path.to_string_lossy().to_string(),
            args: vec![],
            enabled: true,
            auto_start: true,
            process_limits: fresh::services::process_limits::ProcessLimits::default(),
            initialization_options: None,
            env: Default::default(),
            language_id_overrides: Default::default(),
            root_markers: Default::default(),
            name: None,
            only_features: None,
            except_features: None,
        }]),
    );

    let mut harness =
        EditorTestHarness::with_config_and_working_dir(120, 30, config, project_root.clone())?;

    harness.open_file(&test_file)?;
    harness.process_async_and_render()?;

    harness.wait_until(|h| h.screen_to_string().contains("LSP (on)"))?;

    // Open palette and trigger "Go to LSP Symbol"
    harness.send_key(KeyCode::Char('p'), KeyModifiers::CONTROL)?;
    harness.process_async_and_render()?;
    harness.type_text("Go to LSP Symbol")?;
    harness.send_key(KeyCode::Enter, KeyModifiers::NONE)?;

    harness.wait_for_prompt()?;

    // Wait for symbols to appear in the finder results
    harness.wait_until(|h| h.screen_to_string().contains("[class] MyClass"))?;

    // Navigate down to constructor (second item)
    harness.send_key(KeyCode::Down, KeyModifiers::NONE)?;
    harness.process_async_and_render()?;

    // Verify preview split shows constructor range (lines 2-4) with ">" markers
    harness.wait_until(|h| {
        let s = h.screen_to_string();
        s.contains("*Preview*")
            && s.contains(">    2 │   constructor() {")
            && s.contains(">    3 │     return true;")
            && s.contains(">    4 │   }")
            && !s.contains(">    1 │ class MyClass {")
            && !s.contains(">    5 │")
    })?;

    // Navigate down to myMethod (third item)
    harness.send_key(KeyCode::Down, KeyModifiers::NONE)?;
    harness.process_async_and_render()?;

    // Verify preview split updates to myMethod range (lines 6-8) with ">" markers
    harness.wait_until(|h| {
        let s = h.screen_to_string();
        s.contains("*Preview*")
            && s.contains(">    6 │   myMethod(a: number): number {")
            && s.contains(">    7 │     return a;")
            && s.contains(">    8 │   }")
            && !s.contains(">    1 │ class MyClass {")
            && !s.contains(">    5 │")
            && !s.contains(">    9 │ }")
    })?;

    // Cancel with escape and verify preview split closes
    harness.send_key(KeyCode::Esc, KeyModifiers::NONE)?;
    harness.wait_for_prompt_closed()?;
    harness.wait_until(|h| !h.screen_to_string().contains("*Preview*"))?;

    Ok(())
}
