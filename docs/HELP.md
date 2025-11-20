# Help/Manual Plan

This document captures the analysis and plan for revamping the Help experience.

## Goal
- Replace the bespoke `HelpRenderer` view with a “Keyboard Shortcuts” virtual buffer.
- Introduce a new manual page virtual buffer with links to the documentation.
- Implement both experiences via plugins, so the core can simply show virtual buffers instead of custom UI.

## Key Tasks
1. **Command integration**
   - Retire direct `HelpRenderer` toggling.
   - Reuse `Action::ShowHelp` (and a new manual action) to invoke plugins that create virtual buffers.

2. **Keyboard shortcuts plugin**
   - Query keybinding metadata (likely via a new hook/command) and format it into readable buffer text.
   - Create a read-only virtual buffer titled “Keyboard Shortcuts” whenever `Show Help` runs.

3. **Manual page plugin**
   - Define static/manual content with links to longer docs.
   - Render it through another virtual buffer so it behaves like a normal file (scrollable/selectable).
   - Provide actionable links (open file, URL) via commands or built-in link support.

4. **Core/Docs updates**
   - Rename the legacy help menu entry/command to “Keyboard Shortcuts.”
   - Document the plugin-based approach so future improvements live in `plugins/`.

Next step: implement the plugins and wiring described above so both help surfaces live as virtual buffers controlled by plugins.
