# xdoc

**Create editable PowerPoint decks. Automate document workflows. Give your AI agent a document runtime.**

`@s8fy/xdoc` brings the native **xdoc CLI** to npm. Create and edit `.pptx`
files, export PDF and slide images, extract content for an AI workflow, and
inspect the result through structured reports. Text, shapes, tables, and
supported charts remain native PowerPoint objects you can keep editing.

Build a quarterly review from JSON. Refresh a report from business data.
Restyle an existing deck. Let an agent resolve exact objects, preview its
changes, and leave a record of how the presentation was produced.

## Install and try it

Requires **Node.js 22 or newer**. See [supported platforms](#supported-platforms).

```sh
npm install --global @s8fy/xdoc
xdoc --version
```

Start with an existing presentation and generate a review bundle in one command:

```sh
# Export PDF, slide PNGs, a contact sheet, and AI-ready Markdown
xdoc convert deck.pptx --to pdf,png,md --md-detail ai --contact-sheet --output-dir exports
```

Conversion and native PPTX editing run locally without requiring an Office
installation. Rendering uses xdoc's own backends; available fonts affect the
result. Free mode has [task limits and visual watermarks](#free-mode-and-licensing).

## What you can do

| Goal                                | xdoc gives you                                                                                                                              |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Build an editable deck**          | Declarative JSON patches, slide recipes, text, preset shapes, connectors, images, tables, supported charts, equations, and notes.           |
| **Change an existing presentation** | Inspect its structure, select objects by id, name, or query, and apply focused changes with a non-writing dry-run first.                    |
| **Generate recurring reports**      | Fill PPTX templates from JSON; bind text, table, and chart data; use macros, loops, and conditional patch operations.                       |
| **Refresh a deck's design**         | Apply brand profiles, swap theme/style packs, copy slides between decks, or use native DeckKit skins.                                       |
| **Prepare localization**            | Scan text, plan replacements from supplied translations, and compare styles and layout after editing.                                       |
| **Convert and extract**             | PPTX to PDF, PNG, JSON, Markdown, or text; structured notes, links, fonts, and resource inventories; PDF text/rendering; HTML to Markdown.  |
| **Review before delivery**          | Font, link, asset, accessibility, and Office compatibility checks; static layout diagnostics; rendered previews; semantic and visual diffs. |
| **Connect an AI agent**             | Runtime schemas, versioned JSON reports, structured errors, a local daemon, stdio JSON-RPC, and MCP over stdio.                             |

## Create your first deck from JSON

Save this as `review.patch.json`. It creates a title slide and a KPI slide
using built-in recipes:

```json
{
  "schemaVersion": "pptx-patch/v1",
  "ops": [
    {
      "op": "add-slide",
      "recipe": {
        "kind": "title",
        "title": "Quarterly momentum",
        "subtitle": "A business review built with xdoc"
      }
    },
    {
      "op": "add-slide",
      "recipe": {
        "kind": "kpi-grid",
        "title": "Growth at a glance",
        "items": [
          { "label": "Revenue", "value": "$2.4M", "delta": "+18%" },
          { "label": "Customers", "value": "1,280", "delta": "+22%" },
          { "label": "Retention", "value": "98%", "delta": "+2 pts" }
        ]
      }
    }
  ]
}
```

Validate the plan, create the deck, and render a preview:

```sh
# Resolve and simulate the patch without writing the presentation
xdoc pptx apply --patch review.patch.json --output review.pptx --dry-run --json

# Create review.pptx and its review.pptx.xdoc.json sidecar
xdoc pptx apply --patch review.patch.json --output review.pptx --json

# Render PNGs and a contact sheet
xdoc pptx preview review.pptx --output-dir review-previews --contact-sheet --json
```

Open `review.pptx` in PowerPoint and edit the generated text and shapes.
Change the KPI values in JSON to generate another review, or explore recipes
such as `timeline`, `roadmap`, `process-flow`, `comparison-table`, and `gantt`.
Compose individual operations to add charts, tables, diagrams, and supported
animations or transitions. Patch `slide`
indexes start at **0**, while CLI `--slides` selections start at **1**.

Existing output paths are protected by default. Add `--overwrite` when you
intend to replace a previous output.

## Turn everyday deck work into commands

### Inspect, target, and edit

Find the actual PowerPoint objects before constructing an edit patch:

```sh
xdoc pptx inspect deck.pptx --json
xdoc pptx select deck.pptx --query '{"textRegex":"Revenue"}' --json

# edit.patch.json contains your schema-valid changes to the selected objects
xdoc pptx apply --patch edit.patch.json --input deck.pptx --output updated.pptx --dry-run --json
xdoc pptx apply --patch edit.patch.json --input deck.pptx --output updated.pptx --json
```

Inspect supplies object identity, text, geometry, layouts, and styles. Selectors
resolve targets deterministically; ambiguous matches produce an error with
candidates. Patch operations are adopted only after the full operation set
succeeds. The commands above write a separate candidate for review.

### Fill a template or try a new look

Use your own `template.pptx`, business data in `data.json`, and schema-defined
text/table/chart mappings in `bindings.json`:

```sh
xdoc pptx template-fill data.json --template template.pptx --bindings bindings.json --output report.pptx
```

Discover built-in theme packs, then try one on a deck:

```sh
xdoc pptx catalog themes --json
xdoc pptx swap-theme deck.pptx --theme corporate-blue --output themed.pptx
xdoc pptx swap-style deck.pptx --style consulting --output styled.pptx
```

### Extract source material and convert batches

```sh
# Extract the outline, resource inventory, notes, links, and fonts
xdoc extract deck.pptx --parts map,resources,notes,links,fonts --pretty --output artifacts.json

# Read text from a PDF and normalize a local HTML page to Markdown
xdoc pdf extract-text source.pdf --json --pretty
xdoc html2md page.html --output page.md

# Convert a directory and retain a structured batch summary
xdoc convert ./decks --recursive --to pdf --output-dir ./converted --report batch.json
```

PDF text and HTML Markdown can feed a brief or an agent's content pipeline.
Creating the presentation then uses recipes, patches, or a PPTX template.

### Check the result and retain the evidence

```sh
# Include accessibility alongside the standard preflight checks
xdoc check updated.pptx --checks all --output preflight.json

# Check static layout risks and compare the source with the candidate
xdoc pptx vision-check updated.pptx --json
xdoc pptx diff deck.pptx updated.pptx --json

# Review the actual rendered slides
xdoc pptx preview updated.pptx --output-dir updated-previews --contact-sheet --json

# Inspect the revision record or replay its patch
xdoc pptx audit --from-sidecar updated.pptx.xdoc.json --json
xdoc pptx replay --from-sidecar updated.pptx.xdoc.json --output replayed.pptx
```

The default `.xdoc.json` sidecar records the materialized patch, runtime
identity, and apply report. Keep the source deck too: replay of an existing-deck
edit requires the recorded input to remain available. Sidecars contain revision
evidence; fresh checks and previews validate the current presentation.

## Built for AI agents

xdoc exposes its own operations, field contracts, examples, catalogs, feature
support, and report formats. An agent can discover the installed runtime,
inspect a deck, construct a patch, dry-run it, apply it, and verify the result
using machine-readable data at each step. Your agent supplies the content,
translations, and design decisions; xdoc executes the document work.

```sh
# Discover patch operations, then ask for the exact fields you need
xdoc schema --mode index
xdoc schema --mode ops --ops add-chart,set-chart-data --minimal

# Explore built-in examples and the complete runtime contract
xdoc schema --mode examples
xdoc schema > runtime-schema.json

# Browse native PowerPoint shapes
xdoc pptx catalog shapes --json
```

The **0.6.0** runtime exposes **58 patch operations, 18 slide recipe kinds,
182 preset shapes, 9 theme packs, and 4 style packs**. Chart types and advanced
features carry individual support statuses. Use the installed schema to choose
supported operations and read the scope of partial or preserve-only features.

Choose the process interface that fits your host:

| Interface      | Entry point                                                 | Use it for                                                                 |
| -------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| CLI            | `xdoc pptx ... --json`                                      | Local scripts and individual operations.                                   |
| Local daemon   | `xdoc daemon start`, then `inspect`/`apply` with `--daemon` | Keeping parsed deck sessions in memory across local steps.                 |
| Stdio JSON-RPC | `xdoc json-rpc`                                             | A host managing a persistent child process through JSON-RPC 2.0.           |
| MCP over stdio | `xdoc mcp`                                                  | An MCP client discovering schemas, inspecting decks, and applying patches. |

For an MCP client that accepts `mcpServers` configuration:

```json
{
  "mcpServers": {
    "xdoc": {
      "command": "xdoc",
      "args": ["mcp"]
    }
  }
}
```

The MCP adapter exposes `xdoc_schema`, `pptx_inspect`, and `pptx_apply`.
Conversion, previews, and other checks use the CLI. For repeatable integrations,
pin the npm version and capture that executable's schema. This package exposes
the `xdoc` command; process arguments, stdio protocols, and JSON reports form
the public integration boundary.

## Supported platforms

| Operating system  | Architecture          | Binary package           |
| ----------------- | --------------------- | ------------------------ |
| Linux             | arm64                 | `@s8fy/xdoc-linux-arm64` |
| Linux             | x64                   | `@s8fy/xdoc-linux-x64`   |
| macOS 13 or newer | arm64 (Apple Silicon) | `@s8fy/xdoc-macos-arm64` |
| Windows           | x64                   | `@s8fy/xdoc-windows-x64` |

npm selects an exact-version platform package containing the native executable
and bundled PDFium backend. Install scripts do not download binaries from an
external release server. Unsupported operating systems, architectures, or
macOS versions receive an actionable error.

## Scope and compatibility

- **Current inputs:** PPTX, PDF, and HTML, plus JSON patches, recipes, and data
  bindings for PPTX authoring. DOCX and XLSX conversion remain reserved.
- **Editing and preservation:** ordinary PowerPoint objects have native edit
  paths. Complex animation, SmartArt, and other advanced features have their
  own supported, partial, preserve-only, or unsupported status.
- **Rendering and review:** font availability and the selected feature affect
  output. Static checks, rendered previews, and target-Office compatibility
  reports answer different questions; review the rendered result for delivery.

## Free mode and licensing

Free mode provides all core features for **single-user local use**, with up to
**10 slides per task** and **5 MiB of compressed PPTX inputs combined**.
Visual outputs carry an `XDOC DEMO` watermark. No account or license credential
is required to start; tasks exceeding the Free limits are denied.

Personal and Enterprise licenses are offline entitlements that remove the
plan-level slide/PPTX byte limits and new plan watermarks. Local scripts and a
per-user daemon are included in the launch plans; CI, shared servers, and
Service/API use are outside those plans.

The public packages use the
[PolyForm Noncommercial License 1.0.0](https://github.com/hustcer/workers/blob/main/xdoc-npm/LICENSE)
unless separately licensed. Runtime access and legal usage rights are separate;
commercial use requires the applicable separate terms. Platform packages also
retain the bundled PDFium third-party license notices.

## Support and package maintenance

Report installation, platform selection, and launcher issues in the
[`hustcer/workers` issue tracker](https://github.com/hustcer/workers/issues).
For native runtime behavior, use the upstream support channel supplied with
your xdoc distribution or license.

This directory maintains npm packaging and release automation. Native release
assets are pinned to reviewed SHA-256 digests in
[`release-lock.json`](https://github.com/hustcer/workers/blob/main/xdoc-npm/release-lock.json).
See the
[maintainer guide](https://github.com/hustcer/workers/blob/main/xdoc-npm/CONTRIBUTING.md)
for packaging and release checks. To keep exploring the CLI, start with
`xdoc schema --mode examples` or `xdoc pptx <action> --help`.
