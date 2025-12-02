/// <reference path="../types/fresh.d.ts" />

import { PanelManager, NavigationController } from "./lib/index.ts";

/**
 * Multi-File Search & Replace Plugin
 *
 * Provides project-wide search and replace functionality using git grep.
 * Shows results in a virtual buffer split with preview and confirmation.
 */

// Result item structure
interface SearchResult {
  file: string;
  line: number;
  column: number;
  content: string;
  selected: boolean; // Whether this result will be replaced
}

// Maximum results to display
const MAX_RESULTS = 200;

// Search state
let searchPattern: string = "";
let replaceText: string = "";
let searchRegex: boolean = false;

// Panel and navigation state
const panel = new PanelManager("*Search/Replace*", "search-replace-list");
const nav = new NavigationController<SearchResult>({
  itemLabel: "Match",
  wrap: false,
});

// Define the search-replace mode with keybindings
editor.defineMode(
  "search-replace-list",
  null,
  [
    ["Return", "search_replace_preview"],
    ["space", "search_replace_toggle_item"],
    ["a", "search_replace_select_all"],
    ["n", "search_replace_select_none"],
    ["r", "search_replace_execute"],
    ["q", "search_replace_close"],
    ["Escape", "search_replace_close"],
  ],
  true // read-only
);

// Get relative path for display
function getRelativePath(filePath: string): string {
  const cwd = editor.getCwd();
  if (filePath.startsWith(cwd)) {
    return filePath.slice(cwd.length + 1);
  }
  return filePath;
}

// Parse git grep output
function parseGitGrepLine(line: string): SearchResult | null {
  const match = line.match(/^([^:]+):(\d+):(\d+):(.*)$/);
  if (match) {
    return {
      file: match[1],
      line: parseInt(match[2], 10),
      column: parseInt(match[3], 10),
      content: match[4],
      selected: true, // Selected by default
    };
  }
  return null;
}

// Format a result for display
function formatResult(item: SearchResult, index: number): string {
  const checkbox = item.selected ? "[x]" : "[ ]";
  const displayPath = getRelativePath(item.file);
  const location = `${displayPath}:${item.line}`;

  // Truncate for display
  const maxLocationLen = 40;
  const truncatedLocation = location.length > maxLocationLen
    ? "..." + location.slice(-(maxLocationLen - 3))
    : location.padEnd(maxLocationLen);

  const trimmedContent = item.content.trim();
  const maxContentLen = 50;
  const displayContent = trimmedContent.length > maxContentLen
    ? trimmedContent.slice(0, maxContentLen - 3) + "..."
    : trimmedContent;

  return `${checkbox} ${truncatedLocation}  ${displayContent}\n`;
}

// Build panel entries
function buildPanelEntries(): TextPropertyEntry[] {
  const entries: TextPropertyEntry[] = [];
  const results = nav.getItems();

  // Header
  const selectedCount = results.filter(r => r.selected).length;
  entries.push({
    text: `═══ Search & Replace ═══\n`,
    properties: { type: "header" },
  });
  entries.push({
    text: `Search:  "${searchPattern}"${searchRegex ? " (regex)" : ""}\n`,
    properties: { type: "info" },
  });
  entries.push({
    text: `Replace: "${replaceText}"\n`,
    properties: { type: "info" },
  });
  entries.push({
    text: `\n`,
    properties: { type: "spacer" },
  });

  if (results.length === 0) {
    entries.push({
      text: "  No matches found\n",
      properties: { type: "empty" },
    });
  } else {
    // Results header
    const limitNote = results.length >= MAX_RESULTS ? ` (limited to ${MAX_RESULTS})` : "";
    entries.push({
      text: `Results: ${results.length}${limitNote} (${selectedCount} selected)\n`,
      properties: { type: "count" },
    });
    entries.push({
      text: `\n`,
      properties: { type: "spacer" },
    });

    // Add each result
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      entries.push({
        text: formatResult(result, i),
        properties: {
          type: "result",
          index: i,
          location: {
            file: result.file,
            line: result.line,
            column: result.column,
          },
        },
      });
    }
  }

  // Footer
  entries.push({
    text: `───────────────────────────────────────────────────────────────────────────────\n`,
    properties: { type: "separator" },
  });
  entries.push({
    text: `[SPC] toggle  [a] all  [n] none  [r] REPLACE  [RET] preview  [q] close\n`,
    properties: { type: "help" },
  });

  return entries;
}

// Update panel content
function updatePanelContent(): void {
  if (panel.isOpen) {
    panel.updateContent(buildPanelEntries());
  }
}

// Perform the search
async function performSearch(pattern: string, replace: string, isRegex: boolean): Promise<void> {
  searchPattern = pattern;
  replaceText = replace;
  searchRegex = isRegex;

  // Build git grep args
  const args = ["grep", "-n", "--column", "-I"];
  if (isRegex) {
    args.push("-E"); // Extended regex
  } else {
    args.push("-F"); // Fixed string
  }
  args.push("--", pattern);

  try {
    const result = await editor.spawnProcess("git", args);

    const results: SearchResult[] = [];

    if (result.exit_code === 0) {
      for (const line of result.stdout.split("\n")) {
        if (!line.trim()) continue;
        const match = parseGitGrepLine(line);
        if (match) {
          results.push(match);
          if (results.length >= MAX_RESULTS) break;
        }
      }
    }

    nav.setItems(results);

    if (results.length === 0) {
      editor.setStatus(`No matches found for "${pattern}"`);
    } else {
      editor.setStatus(`Found ${results.length} matches`);
    }
  } catch (e) {
    editor.setStatus(`Search error: ${e}`);
    nav.setItems([]);
  }
}

// Show the search results panel
async function showResultsPanel(): Promise<void> {
  if (panel.isOpen) {
    updatePanelContent();
    return;
  }

  try {
    await panel.open({
      entries: buildPanelEntries(),
      ratio: 0.4, // 60/40 split
    });
    editor.debug(`Search/Replace panel opened with buffer ID ${panel.bufferId}`);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    editor.setStatus("Failed to open search/replace panel");
    editor.debug(`ERROR: panel.open failed: ${errorMessage}`);
  }
}

// Execute replacements
async function executeReplacements(): Promise<void> {
  const selectedResults = nav.getItems().filter(r => r.selected);

  if (selectedResults.length === 0) {
    editor.setStatus("No items selected for replacement");
    return;
  }

  // Group by file
  const fileGroups: Map<string, SearchResult[]> = new Map();
  for (const result of selectedResults) {
    if (!fileGroups.has(result.file)) {
      fileGroups.set(result.file, []);
    }
    fileGroups.get(result.file)!.push(result);
  }

  let filesModified = 0;
  let replacementsCount = 0;
  const errors: string[] = [];

  for (const [filePath, results] of fileGroups) {
    try {
      // Read file
      const content = await editor.readFile(filePath);
      const lines = content.split("\n");

      // Sort results by line (descending) to avoid offset issues
      const sortedResults = [...results].sort((a, b) => {
        if (a.line !== b.line) return b.line - a.line;
        return b.column - a.column;
      });

      // Apply replacements
      for (const result of sortedResults) {
        const lineIndex = result.line - 1;
        if (lineIndex >= 0 && lineIndex < lines.length) {
          let line = lines[lineIndex];

          if (searchRegex) {
            // Regex replacement
            const regex = new RegExp(searchPattern, "g");
            lines[lineIndex] = line.replace(regex, replaceText);
          } else {
            // Simple string replacement (all occurrences in line)
            lines[lineIndex] = line.split(searchPattern).join(replaceText);
          }
          replacementsCount++;
        }
      }

      // Write back
      const newContent = lines.join("\n");
      await editor.writeFile(filePath, newContent);
      filesModified++;

    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e);
      errors.push(`${filePath}: ${errorMessage}`);
    }
  }

  // Report results
  if (errors.length > 0) {
    editor.setStatus(`Replaced in ${filesModified} files (${errors.length} errors)`);
    editor.debug(`Replacement errors: ${errors.join(", ")}`);
  } else {
    editor.setStatus(`Replaced ${replacementsCount} occurrences in ${filesModified} files`);
  }

  // Close panel after replacement
  globalThis.search_replace_close();
}

// Start search/replace workflow
globalThis.start_search_replace = function(): void {
  nav.reset();
  searchPattern = "";
  replaceText = "";

  editor.startPrompt("Search (in project): ", "search-replace-search");
  editor.setStatus("Enter search pattern...");
};

// Handle search prompt confirmation
globalThis.onSearchReplaceSearchConfirmed = function(args: {
  prompt_type: string;
  selected_index: number | null;
  input: string;
}): boolean {
  if (args.prompt_type !== "search-replace-search") {
    return true;
  }

  const pattern = args.input.trim();
  if (!pattern) {
    editor.setStatus("Search cancelled - empty pattern");
    return true;
  }

  searchPattern = pattern;

  // Ask for replacement text
  editor.startPrompt("Replace with: ", "search-replace-replace");
  return true;
};

// Handle replace prompt confirmation
globalThis.onSearchReplaceReplaceConfirmed = async function(args: {
  prompt_type: string;
  selected_index: number | null;
  input: string;
}): Promise<boolean> {
  if (args.prompt_type !== "search-replace-replace") {
    return true;
  }

  replaceText = args.input; // Can be empty for deletion

  // Perform search and show results
  await performSearch(searchPattern, replaceText, false);
  await showResultsPanel();

  return true;
};

// Handle prompt cancellation
globalThis.onSearchReplacePromptCancelled = function(args: {
  prompt_type: string;
}): boolean {
  if (args.prompt_type !== "search-replace-search" &&
      args.prompt_type !== "search-replace-replace") {
    return true;
  }

  editor.setStatus("Search/Replace cancelled");
  return true;
};

// Toggle selection of current item
globalThis.search_replace_toggle_item = function(): void {
  if (panel.bufferId === null || nav.isEmpty) return;

  const props = editor.getTextPropertiesAtCursor(panel.bufferId);
  const results = nav.getItems();
  if (props.length > 0 && typeof props[0].index === "number") {
    const index = props[0].index as number;
    if (index >= 0 && index < results.length) {
      results[index].selected = !results[index].selected;
      updatePanelContent();
      const selected = results.filter(r => r.selected).length;
      editor.setStatus(`${selected}/${results.length} selected`);
    }
  }
};

// Select all items
globalThis.search_replace_select_all = function(): void {
  const results = nav.getItems();
  for (const result of results) {
    result.selected = true;
  }
  updatePanelContent();
  editor.setStatus(`${results.length}/${results.length} selected`);
};

// Select no items
globalThis.search_replace_select_none = function(): void {
  const results = nav.getItems();
  for (const result of results) {
    result.selected = false;
  }
  updatePanelContent();
  editor.setStatus(`0/${results.length} selected`);
};

// Execute replacement
globalThis.search_replace_execute = function(): void {
  const selected = nav.getItems().filter(r => r.selected).length;
  if (selected === 0) {
    editor.setStatus("No items selected");
    return;
  }

  editor.setStatus(`Replacing ${selected} occurrences...`);
  executeReplacements();
};

// Preview current item (jump to location)
globalThis.search_replace_preview = function(): void {
  if (panel.sourceSplitId === null || panel.bufferId === null) return;

  const props = editor.getTextPropertiesAtCursor(panel.bufferId);
  if (props.length > 0) {
    const location = props[0].location as { file: string; line: number; column: number } | undefined;
    if (location) {
      editor.openFileInSplit(panel.sourceSplitId, location.file, location.line, location.column);
      editor.setStatus(`Preview: ${getRelativePath(location.file)}:${location.line}`);
    }
  }
};

// Close the panel
globalThis.search_replace_close = function(): void {
  if (!panel.isOpen) return;

  panel.close();
  nav.reset();
  editor.setStatus("Search/Replace closed");
};

// Register event handlers
editor.on("prompt_confirmed", "onSearchReplaceSearchConfirmed");
editor.on("prompt_confirmed", "onSearchReplaceReplaceConfirmed");
editor.on("prompt_cancelled", "onSearchReplacePromptCancelled");

// Register command
editor.registerCommand(
  "Search and Replace in Project",
  "Search and replace text across all git-tracked files",
  "start_search_replace",
  "normal"
);

// Plugin initialization
editor.debug("Search & Replace plugin loaded");
editor.setStatus("Search & Replace plugin ready");
