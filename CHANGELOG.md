# Changelog

All notable changes to SM CLI will be documented here.

## [1.0.21] - 2026-06-08

### Notes
- Version-only bump to force `pub global activate` to regenerate the
  snapshot. The 1.0.20 activation cached a snapshot from before the
  Confirm-prompt edit landed; bumping the version invalidates that
  cache. No behavior changes vs. 1.0.20.

## [1.0.20] - 2026-06-08

### Changed
- The auto-scaffold-on-missing-feature behavior in `sm ai implement` now
  asks first instead of running silently:
  `? Auto-scaffold "welcome" now and continue? (Y/n) ›`
  Default is Yes — hit Enter to proceed. Pressing N aborts cleanly with
  the original "run sm make feature first" hint.

## [1.0.19] - 2026-06-08

### Changed
- `sm ai implement <project> <feature> --design <path>` now auto-scaffolds
  the feature if it doesn't exist, instead of telling the user to run
  `sm make feature` first and bailing. The full flow becomes a single
  command: scaffold → implement → split into widgets. If the feature
  name is invalid (fails the snake_case regex), `make feature` still
  rejects it and `implement` aborts with a clear error.

## [1.0.18] - 2026-06-08

### Added
- Multi-pass planning. When clustered representatives exceed what fits
  in one API call, `sm ai` now runs up to 4 passes (12 images each),
  then unions the features + extra packages across passes. Previously
  the cap silently dropped clusters past the 12th; now every cluster
  is seen by the AI at least once. Theme tokens are taken from the
  first pass (consistent — averaging produced muddy colors).
- The console summary now shows pass counts and per-batch sizes, e.g.
  `🔁 Planning across 2 pass(es) so every cluster is seen
      (18 representatives, batches of 12/6).`

## [1.0.17] - 2026-06-08

### Fixed
- `sm ai --design <folder>` still 503-ing on Gemini even with 18 large
  mobile mockups. Two tighter caps now apply in `_capForPlan`:
  - Image count cap lowered from 30 → 12 (Gemini's server-side image-
    processing deadline trips at ~15+ large mockups in one request).
  - Byte-budget cap of 8 MB raw (~10.7 MB base64-encoded). After even-
    sampling, images are added until the next one would exceed the
    budget; the rest are dropped with a clear warning.
- The send summary now prints total payload size in MB:
  `🖼️  Sending 12 representative image(s) (5.4 MB) to the AI...`

## [1.0.16] - 2026-06-08

### Added
- Filename-prefix clustering + 30-image cap on `sm ai --design <folder>`.
  Folders of 50+ screens used to time out the vision API (Gemini 503,
  Claude 400) because every image was sent in one request. Now `sm`:
  - Groups files by normalized prefix — `Login.png`, `Login-1.png`,
    `02 Login.png`, `Login_filled.png` all cluster under `login` and one
    representative is sent.
  - Caps the request at 30 images even after clustering (even-samples if
    still over).
  - Prints the cluster summary so you can see what was sent vs dropped
    and rename files if the grouping looks wrong.
  - **Saves the full original set** to `<project>/design/` regardless of
    the cap — the cap only affects what the AI sees during planning.

## [1.0.15] - 2026-06-08

### Improved
- Figma `429` errors now read the `Retry-After` header. When the reset
  window is >10 minutes (i.e. the daily image-render quota is exhausted,
  not a transient throttle), the error explains the situation and points
  at the manual-export workaround: export frames from Figma → use
  `--design <folder>` instead. No more silent confusion when a Pro-tier
  account hits the `/images` paywall.

## [1.0.14] - 2026-06-08

### Fixed
- Figma `429 Rate limit exceeded` now triggers automatic backoff: retry
  after 5s → 15s → 30s, with progress printed. An 800ms pause is also
  inserted between successful batches so we don't burst into the limit.
  Sustained 429s surface a clear "wait a minute, then retry" message.

## [1.0.13] - 2026-06-08

### Fixed
- `Figma /images failed (400): Render timeout` on files with many or
  large frames. Render calls are now batched (5 frames per request),
  default scale lowered from 2 to 1, and INSTANCE / COMPONENT_SET are
  excluded from auto-discovery (those are duplicates and variant
  collections, not screens). Progress is printed per batch.

## [1.0.12] - 2026-06-08

### Fixed
- `sm ai --figma <key>` auto-discovery used to scan only the first page's
  direct children for FRAME/COMPONENT nodes — anything inside a SECTION
  or on a later page was invisible. Now walks every page and descends
  into SECTION containers, picking up FRAME / COMPONENT / COMPONENT_SET /
  INSTANCE. The "no frames found" error now explains where to find
  node IDs in Figma URLs.
- `--figma-node` accepts both URL-style IDs (`1-23`, with dashes) and
  API-style IDs (`1:23`, with colons). Paste straight from the URL.

## [1.0.11] - 2026-06-08

### Changed
- `sm ai --design <...>` now treats the plain-text feature brief as
  additive instead of overriding it. Designs are still primary (one
  feature per distinct screen), but features named in the brief that
  don't appear in any screen are also included as stubs. Previously
  the "don't invent features not implied by the designs" rule silently
  dropped brief-only features.

## [1.0.10] - 2026-06-08

### Changed
- `sm ai implement` now returns JSON `{screen, widgets[]}` and the design
  skill enforces a ~150-line file cap. Screens that would exceed that
  cap are auto-split into reusable widgets written to
  `lib/features/<feature>/presentation/widgets/`. The screen file imports
  each extracted widget with a relative path.
- `max_tokens` raised to 8192 across Claude / OpenAI / Gemini to fit the
  larger multi-file payload; provider timeouts raised to 180s.

## [1.0.9] - 2026-06-08

### Added
- `sm ai implement <project> <feature> --design <path>` — rewrites a feature's
  screen file to match a reference screenshot using AppTheme tokens and
  state-management-aware widget patterns (Riverpod / Bloc / GetX / Provider).
  Backs up the original to `<file>.bak`.
- `sm ai <project> --design <path>` — local image file, folder, comma-separated
  list, or repeated flag. Images are sent to the AI as multimodal references
  and copied into `<project>/design/` for provenance.
- `sm ai <project> --figma <key> [--figma-node <id>]` — renders Figma frames
  via the REST API. Personal Access Tokens are free; stored in
  `~/.sm_cli/credentials.json` or read from `FIGMA_TOKEN`.
- `design/` folder added to every scaffolded project with a README.
- Embedded `skills/design-skill.md` (the flutter-frontend skill) into AI prompts
  so plans favor bold, distinctive visual languages and varied font pairings
  via `google_fonts`. Build-time generator at `tool/generate_skills.dart`.
- ProjectPlan now captures `visual_language`, `display_font`, `body_font`
  alongside `theme_mode` / `seed_color`.

### Fixed
- `theme_generator.dart` previously hardcoded `Colors.blue` and ignored
  `theme_mode` / `seed_color` from the AI plan — now wires both through.
- Gemini truncation: disabled thinking (`thinkingBudget: 0`) and raised
  `maxOutputTokens` so the model finishes the JSON / code instead of
  cutting off mid-output.

### Changed
- Claude/Gemini/OpenAI providers gained multimodal `plan(assets: [...])` and
  `generateCode(...)` paths. Grok throws a clear `UnimplementedError` —
  switch provider with `sm ai config` to use design refs.

## [1.0.8] - 2026-05-28

### Added
- Multiple features generate in one command
  `sm make feature my_app auth home profile`

## [1.0.7] - 2026-05-27

### Added
- `sm remove feature <project> <feature>` — feature delete with auto route cleanup
- `sm remove feature <project> <feature> --force` — skip confirmation
- `sm list` now shows file count per feature

### Improved
- Better `sm init` output — next steps clearly shown after project creation

## [1.0.6] - 2026-05-27

### Fixed
- `sm make feature <project> <feature>` now works correctly from outside the project folder
- Feature folder no longer created inside `features/` with project name — correct path is `features/auth/` not `features/my_app/`

### Changed
- Commands now work from outside the project folder — no need to `cd` into project
- `sm make feature my_app auth` — project name required
- `sm make api my_app` — project name required
- `sm list my_app` — project name required

---


## [1.0.5] - 2026-05-24

### Added
- `sm list` — project mein saare features list karta hai with state management info
- Feature name validation — sirf `snake_case` allow hoga
- Existing feature overwrite protection — warning deta hai

### Fixed
- `sm list` command properly registered

---

## [1.0.4] - 2026-05-23

### Fixed
- `sm make feature` and `sm make api` now only work inside the project folder — clear error message shown when run from outside
- Feature name now generates correctly

### Improved
- `model` now auto-generates `fromJson` and `toJson` methods
- `usecase` now auto-generates `call()` method
- `remote_datasource` now auto-generates basic structure with Dio
- `repository_impl` now includes commented hints for implementation

---

## [1.0.3] - 2026-05-23

### Fixed
- Project name is now optional — after `cd my_app`, just run `sm make feature auth`
- `sm make api` works without project name as well
- GetX now correctly generates `screens` folder

---

## [1.0.2] - 2026-05-23

### Fixed
- `sm make feature` now works from inside the project folder

---

## [1.0.1] - 2026-05-23

### Added
- Flutter project initializer with clean architecture
- Multiple state management support — Riverpod, Bloc, GetX, Provider
- Feature generator with auto state management detection
- Bloc structure — bloc, event, state files auto generated
- GetX structure — controller, view, binding auto generated
- Riverpod & Provider — StateNotifier provider auto generated
- API layer generator — Dio client, interceptors, response wrapper
- GoRouter integration with auto route & constant generation
- Light & dark theme setup with Material 3
- Project config (`.sm_cli_config`) auto saved on init
- `--help` and `--version` flags
- Direct flags — `--riverpod`, `--bloc`, `--getx`, `--provider`

### Fixed
- Removed unused `calculate()` function from `lib/sm_cli.dart`