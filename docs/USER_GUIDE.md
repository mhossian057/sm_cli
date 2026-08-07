# SM CLI — Complete User Guide

**Version 1.0.21** · A production-grade Dart CLI for scaffolding Flutter apps with clean architecture, AI-assisted planning, and Figma-to-code generation.

---

## Table of Contents

1. [What is SM CLI?](#1-what-is-sm-cli)
2. [Installation & Setup](#2-installation--setup)
3. [Quick Start (5-Minute Tour)](#3-quick-start-5-minute-tour)
4. [Command Reference](#4-command-reference)
    - [`sm init` — Create a new project](#41-sm-init)
    - [`sm make feature` — Scaffold a feature](#42-sm-make-feature)
    - [`sm make api` — Generate the API layer](#43-sm-make-api)
    - [`sm remove feature` — Delete a feature](#44-sm-remove-feature)
    - [`sm list` — Show project features](#45-sm-list)
    - [`sm ai` — AI project planner](#46-sm-ai)
    - [`sm ai config` — Manage AI credentials](#47-sm-ai-config)
    - [`sm ai implement` — Rebuild a screen from a design](#48-sm-ai-implement)
    - [`sm --help` / `sm --version`](#49-sm---help--sm---version)
5. [Generated Project Structure](#5-generated-project-structure)
6. [State Management Options](#6-state-management-options)
7. [AI Providers & Credentials](#7-ai-providers--credentials)
8. [Figma Integration](#8-figma-integration)
9. [The `manifest.json` Contract](#9-the-manifestjson-contract)
10. [End-to-End Workflows](#10-end-to-end-workflows)
11. [Configuration Files](#11-configuration-files)
12. [Troubleshooting](#12-troubleshooting)
13. [FAQ](#13-faq)

---

## 1. What is SM CLI?

`sm_cli` (executable `sm`) is a Dart CLI that generates Flutter apps for you. It:

- Wraps `flutter create` and `flutter pub add` with an opinionated **clean-architecture** folder tree.
- Supports **four state-management libraries** — Riverpod, Bloc, GetX, Provider — and remembers your choice per project.
- Auto-wires **GoRouter** routes when you add a feature.
- Generates a **Dio-based API layer** on demand.
- Uses **AI (Claude / OpenAI / Gemini / Grok)** to plan features, pick a visual language, and even implement whole screens from design mockups.
- Integrates with **Figma** to render frames straight into your project as design references.

The output is a real Flutter app. `sm` runs once, then you edit the code like any Flutter project.

---

## 2. Installation & Setup

### Prerequisites

| Tool | Minimum version | Purpose |
|------|-----------------|---------|
| Dart SDK | 3.0.0 | Runs the CLI |
| Flutter | Any current stable | Shelled out by `sm init` and `sm make api` |

Verify both are on your PATH:

```bash
dart --version
flutter --version
```

### Install SM CLI

```bash
dart pub global activate sm_cli
```

### Add Dart's global bin to your PATH

The `dart pub global activate` command installs `sm` into `~/.pub-cache/bin`, which is **not** on your PATH by default. Pick the block that matches your shell and append it to your rc file.

**zsh (default on macOS)**

```bash
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.zshrc
source ~/.zshrc
```

**bash (default on most Linux distros)**

```bash
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.bashrc
source ~/.bashrc
```

**fish**

```fish
fish_add_path $HOME/.pub-cache/bin
```

**Windows (PowerShell, admin)**

```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  $env:Path + ";$env:LOCALAPPDATA\Pub\Cache\bin",
  "User"
)
```
Close and reopen the terminal after running.

### Verify the install

```bash
which sm                         # → /Users/you/.pub-cache/bin/sm
sm --version                     # → sm_cli version 1.0.21
sm --help
```

If `which sm` prints nothing, the PATH edit didn't take effect — open a fresh terminal window and try again.

### Upgrade to the latest version

```bash
dart pub global activate sm_cli          # always pulls the newest published version
sm --version                             # confirm it changed
```

### Uninstall

```bash
dart pub global deactivate sm_cli
rm -rf ~/.sm_cli                         # (optional) remove stored credentials
```

---

### Install from source (contributors only)

```bash
git clone https://github.com/flutterbysunny/sm_cli.git
cd sm_cli
dart pub get                             # fetch dependencies
dart pub global activate --source path . # install this checkout as `sm`
sm --version                             # confirm
```

### Install from Git (any repo, any branch, no clone needed)

Use this when you want to install `sm` **directly from GitHub** — for example, to try an unreleased branch, install a fork, or ship a private version to your team without publishing to pub.dev.

**Basic form** — installs the default branch (usually `main`):

```bash
dart pub global activate --source git https://github.com/flutterbysunny/sm_cli.git
```

**Pin to a branch** (e.g. `develop`, `feat/ai-planner`):

```bash
dart pub global activate --source git \
  --git-ref develop \
  https://github.com/flutterbysunny/sm_cli.git
```

**Pin to a specific commit** (reproducible; safest for teams):

```bash
dart pub global activate --source git \
  --git-ref a069954 \
  https://github.com/flutterbysunny/sm_cli.git
```

**Pin to a tag** (e.g. `v1.0.21`):

```bash
dart pub global activate --source git \
  --git-ref v1.0.21 \
  https://github.com/flutterbysunny/sm_cli.git
```

**From a fork:**

```bash
dart pub global activate --source git \
  https://github.com/<your-username>/sm_cli.git
```

**From a private repo** (uses your SSH key — set up in `~/.ssh/`):

```bash
dart pub global activate --source git \
  git@github.com:your-org/sm_cli.git
```

**If the Dart package lives in a subdirectory** of the repo (not the case for `sm_cli`, but handy to know):

```bash
dart pub global activate --source git \
  --git-path packages/sm_cli \
  https://github.com/your-org/monorepo.git
```

**Verify it worked:**

```bash
which sm
sm --version
```

**Updating to the latest commit on that branch:**

Re-run the same `activate` command. Pub re-fetches from git and rebuilds.

```bash
dart pub global activate --source git --git-ref develop \
  https://github.com/flutterbysunny/sm_cli.git
```

**Switching back to the pub.dev version:**

```bash
dart pub global deactivate sm_cli
dart pub global activate sm_cli
```

**Common pitfalls**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Repository not found` | Private repo without SSH, or wrong URL | Use `git@github.com:...` form and confirm `ssh -T git@github.com` works |
| `Could not find a file named "pubspec.yaml"` | Wrong `--git-path` for a monorepo | Point `--git-path` at the folder that contains `pubspec.yaml` |
| Old code still runs after re-activating | Stale snapshot in `~/.pub-cache/bin` | `dart pub global deactivate sm_cli` then re-run activate |
| `Reference ... not found` | Branch/tag/commit doesn't exist on remote | `git ls-remote <url>` to list valid refs |

---

### Adding sm_cli as a library dependency (rare)

`sm_cli` is designed as a **CLI**, not a library — most users don't need this. But if you want to import its generators or services from another Dart project, add it to `pubspec.yaml`:

```yaml
dependencies:
  sm_cli:
    git:
      url: https://github.com/flutterbysunny/sm_cli.git
      ref: main            # branch, tag, or commit SHA
      # path: packages/sm_cli   # only if it's in a subdirectory
```

Then:

```bash
dart pub get
```

Import in your Dart code:

```dart
import 'package:sm_cli/commands/init_command.dart';
```

> **Heads up:** the library surface isn't a stable public API — internals may change between versions without notice. Prefer the CLI unless you have a specific reason to embed it.

---

### Fixing the "my source edits don't show up" problem

`dart pub global activate` compiles your CLI into a **pre-compiled snapshot** at:

```
<repo>/.dart_tool/pub/bin/sm_cli/sm_cli.dart-<dart-version>.snapshot
```

Editing source files does **not** invalidate this snapshot. The running `sm` keeps executing the old code until you delete the snapshot and re-activate.

**Fix (run after every source change):**

```bash
# Adjust the path to your local sm_cli checkout
rm -f /Volumes/ADATA/workspace/sm_cli/.dart_tool/pub/bin/sm_cli/sm_cli.dart-*.snapshot
cd /Volumes/ADATA/workspace/sm_cli && dart pub global activate --source path .
```

Generic version (works from anywhere, matches any Dart version):

```bash
rm -f ~/.pub-cache/bin/sm* \
      "$(pwd)"/.dart_tool/pub/bin/sm_cli/sm_cli.dart-*.snapshot
dart pub global activate --source path .
```

Or wrap it in a one-shot alias — add to your shell rc:

```bash
alias sm-rebuild='rm -f /Volumes/ADATA/workspace/sm_cli/.dart_tool/pub/bin/sm_cli/sm_cli.dart-*.snapshot && \
  (cd /Volumes/ADATA/workspace/sm_cli && dart pub global activate --source path .)'
```

Then just run `sm-rebuild` after editing.

### Common install issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `zsh: command not found: sm` | `~/.pub-cache/bin` not on PATH | Redo the PATH step above, open a new terminal |
| `sm --version` prints an older version after upgrade | Old snapshot in `~/.pub-cache/bin` | `dart pub global deactivate sm_cli && dart pub global activate sm_cli` |
| Source edits don't apply | Stale local snapshot (see above) | Delete `.snapshot` and re-activate |
| `Could not find package sm_cli` | You're behind a proxy or `pub.dev` unreachable | Check `dart pub get` in any project; verify network |
| `Permission denied` on `~/.pub-cache/bin/sm` | File wasn't marked executable | `chmod +x ~/.pub-cache/bin/sm` |
| `flutter: command not found` when running `sm init` | Flutter not on PATH for the same shell | `which flutter` → add to same rc file as Dart |

---

## 3. Quick Start (5-Minute Tour)

```bash
# 1. Create a new project (interactive)
sm init my_app

# 2. Add a feature
sm make feature my_app auth

# 3. Add the API layer
sm make api my_app

# 4. List what you've built
sm list my_app

# 5. Run it
cd my_app && flutter run
```

Prefer no prompts?

```bash
sm init my_app --riverpod
sm make feature my_app auth home profile
```

Have a Figma file or design mockups?

```bash
sm ai my_app --figma <FIGMA_FILE_KEY>
# or
sm ai my_app --design ./mockups --auto-implement
```

---

## 4. Command Reference

Every command follows this shape:

```
sm <command> [<subcommand>] [<positional>...] [--flags]
```

### 4.1 `sm init`

Creates a new Flutter project with clean architecture.

**Signature**
```bash
sm init <project_name> [--riverpod|--bloc|--getx|--provider]
```

**Flags**

| Flag | Short | Effect |
|------|-------|--------|
| `--riverpod` | `-r` | Use Riverpod, skip the state-management prompt |
| `--bloc` | `-b` | Use Bloc |
| `--getx` | `-g` | Use GetX |
| `--provider` | `-p` | Use Provider |

**Interactive prompts (when no flag is passed)**

1. Choose state management: Riverpod / Bloc / GetX / Provider
2. Enable GoRouter? (default: yes)
3. Enable Theme? (default: yes)

**What it does**

1. Runs `flutter create --platforms=android,ios <project_name>`.
2. Adds the clean-architecture folder tree under `lib/`.
3. Writes `main.dart` wrapped for the chosen state management.
4. Generates GoRouter + `AppRoutes` constants (if enabled).
5. Generates `AppTheme` with Material 3 + optional Google Fonts (if enabled).
6. Writes `<project>/.sm_cli_config` so later commands know your choice.
7. Shells out `flutter pub add` for `go_router`, `dio`, and the state-mgmt package.

**Examples**

```bash
sm init my_app                 # interactive
sm init my_app --riverpod      # Riverpod, no prompts
sm init shop_app --bloc        # Bloc
sm init crm --getx             # GetX
```

---

### 4.2 `sm make feature`

Scaffolds one or more features with data/domain/presentation layers, then auto-wires routes.

**Signature**
```bash
sm make feature <project> <feature> [<feature>...]
```

**Feature-name rules**

- Must match `^[a-z][a-z0-9_]*$` (snake_case; letters, digits, underscores).
- Valid: `auth`, `user_profile`, `home_screen`, `order_history`
- Invalid: `Auth` (uppercase), `user-profile` (hyphens), `1auth` (leading digit)

Class names are derived automatically: `user_profile` → `UserProfileScreen`.

**Auto-detects state management** from `.sm_cli_config`. You never re-specify it.

**Generated files (per feature)**

```
lib/features/<feature>/
├── data/
│   ├── datasource/<feature>_remote_datasource.dart
│   ├── models/<feature>_model.dart
│   └── repository/
│       ├── <feature>_repository.dart
│       └── <feature>_repository_impl.dart
├── domain/
│   ├── entities/<feature>_entity.dart
│   ├── repository/<feature>_repository.dart
│   └── usecases/<feature>_usecase.dart
└── presentation/
    ├── screens/<feature>_screen.dart
    ├── widgets/
    └── <state-mgmt-specific folder>
```

State-mgmt-specific folder:
- **Riverpod / Provider** → `providers/<feature>_provider.dart`
- **Bloc** → `bloc/{<feature>_bloc, _event, _state}.dart`
- **GetX** → `controllers/`, `bindings/`, `views/`

**Auto route wiring**

The command mutates two files in place:
- `lib/core/routes/app_routes.dart` — adds `static const <feature> = '/<feature>';`
- `lib/core/routes/app_router.dart` — adds an `import` and a `GoRoute(...)` block

**Examples**

```bash
sm make feature my_app auth
sm make feature my_app home profile settings   # batch
sm make feature shop_app checkout
```

---

### 4.3 `sm make api`

Creates a Dio-based networking layer under `lib/core/network/`.

**Signature**
```bash
sm make api <project>
```

**Generated files**

```
lib/core/network/
├── dio_client.dart               # singleton Dio with logging interceptor
├── api_endpoints.dart            # baseUrl + example endpoints
├── response_wrapper.dart         # ResponseWrapper<T>
├── network_exceptions.dart       # centralized error handler
└── interceptors/
    └── logging_interceptor.dart  # request/response/error logging
```

**Example**

```bash
sm make api my_app
```

Edit `api_endpoints.dart` to set your real `baseUrl` and endpoint constants.

---

### 4.4 `sm remove feature`

Removes a feature folder and reverses the route wiring done by `sm make feature`.

**Signature**
```bash
sm remove feature <project> <feature> [--force]
```

**Flags**

| Flag | Short | Effect |
|------|-------|--------|
| `--force` | `-f` | Skip the confirmation prompt |

**What it does**

1. Deletes `lib/features/<feature>/` recursively.
2. Strips the `static const <feature> = '/<feature>';` line from `app_routes.dart`.
3. Strips the import + `GoRoute(...)` block from `app_router.dart`.

> **Caveat:** route removal uses exact string matching. If you manually edited the emitted route, cleanup may leave dead code — grep for the feature name afterwards.

**Examples**

```bash
sm remove feature my_app auth          # asks for confirmation
sm remove feature my_app auth --force  # no prompt
```

---

### 4.5 `sm list`

Lists every feature in a project with its Dart file count.

**Signature**
```bash
sm list <project>
```

**Example output**

```
📦 my_app Features (Riverpod):

  ✅ auth (12 files)
  ✅ home (10 files)
  ✅ profile (10 files)

Total: 3 feature(s)
```

---

### 4.6 `sm ai`

Uses an LLM to plan a Flutter project (or augment an existing one) from your design assets and a short brief. Optionally builds the whole thing end-to-end.

**Signature**
```bash
sm ai <project> [--design <path>...] [--figma <key>] [--figma-node <id>...] [--auto-implement]
```

**Options**

| Option | Repeatable | Description |
|--------|------------|-------------|
| `--design <path>` | ✅ | File or folder of PNG/JPG/JPEG/WebP mockups |
| `--figma <key>` | — | Figma file key (from the file URL) to render as reference frames |
| `--figma-node <id>` | ✅ | Specific Figma node IDs; defaults to top-level frames |
| `--auto-implement` | — | After scaffolding, run `ai implement` for each mapped feature |

**How it works**

1. **Resolve provider + API key** — reads default from `~/.sm_cli/credentials.json`, then env var, then prompts.
2. **Load design assets** — local files or rendered Figma frames.
3. **Cluster + chunk** — groups duplicate mockups (e.g. `login.png`, `login-1.png`) and splits into up to **4 passes** of **12 images / 8 MB** so no single API call blows up.
4. **Ask a short questionnaire** (only for new projects): scale, budget, feature brief, state management, design brief.
5. **Plan** — the LLM returns a `ProjectPlan` (features, theme, fonts, extra packages, feature→design mapping).
6. **Preview + confirm** — prints the plan; you approve before anything is written.
7. **Generate** — runs `sm init` + `sm make feature ...` under the hood, copies designs into `<project>/design/`, writes `manifest.json`.
8. **Auto-implement (optional)** — if `--auto-implement`, calls `sm ai implement` for every feature that has a design.

**Examples**

```bash
# New project from local mockups
sm ai my_app --design ./mockups

# From a Figma file
sm ai my_app --figma abcXYZ123

# Specific Figma nodes only
sm ai my_app --figma abcXYZ123 --figma-node 1-23 --figma-node 4-56

# End-to-end: plan, scaffold, and rebuild every mapped screen
sm ai my_app --design ./mockups --auto-implement

# Augment an existing project (skips the questionnaire, reads .sm_cli_config)
sm ai my_app --design ./new_screens
```

---

### 4.7 `sm ai config`

Manages the credentials file at `~/.sm_cli/credentials.json`.

**Signature**
```bash
sm ai config [--list | --reset]
```

**Flags**

| Flag | Effect |
|------|--------|
| `--list` | Print configured providers (API keys masked) |
| `--reset` | Wipe all stored credentials (asks for confirmation) |

**Without flags** — opens an interactive menu:

1. List configured providers
2. Set / update an API key
3. Change default provider
4. Change model for a provider
5. Remove a provider
6. Reset all credentials
7. Exit

**Examples**

```bash
sm ai config                    # interactive menu
sm ai config --list             # audit what's stored
sm ai config --reset            # nuke everything
```

**Sample `--list` output**

```
📁 /Users/you/.sm_cli/credentials.json
  Anthropic Claude (default)
    key   : sk-ant-…Uvwxy
    model : claude-sonnet-4-6
  OpenAI ChatGPT
    key   : sk-proj-…Uvwxy
    model : —
```

See [§7 AI Providers & Credentials](#7-ai-providers--credentials) for full details.

---

### 4.8 `sm ai implement`

Rebuilds a single feature's screen from a design mockup. Purely presentation — never touches your data or domain layer.

**Signature**
```bash
sm ai implement <project> <feature> --design <path>
```

**Requirements**

- Project must exist (`<project>/lib` present).
- Feature must exist. If it's missing, the CLI asks whether to scaffold it first.
- `--design` must be a single PNG / JPG / JPEG / WebP file.

**What it does**

1. Reads the current screen file, `AppTheme`, and `.sm_cli_config`.
2. Asks the LLM for a rewrite. The system prompt forces:
    - Root widget is `Scaffold`
    - Colors from `AppTheme`, not hardcoded hex
    - Typography from `Theme.of(context).textTheme`
    - **No** business logic (no `Bloc`, `ChangeNotifier`, `GetxController`, etc.)
    - **No** data-layer changes (repos, models, HTTP)
    - Screens under ~150 lines; longer ones split into `widgets/` files
3. **Backs up the current screen to `<file>.bak`** before overwriting.
4. Writes extracted widgets to `lib/features/<feature>/presentation/widgets/`.
5. Detects imported packages (`package:name/...`), checks pub.dev, and runs `flutter pub add` for real ones. Hallucinated names are skipped with a warning.
6. Runs `dart fix --apply` to resolve any leftover lint issues.
7. Copies the design into `<project>/design/<feature>_<filename>` for future reference.

**Examples**

```bash
sm ai implement my_app auth   --design ./mockups/login.png
sm ai implement my_app home   --design ./mockups/feed.jpg
sm ai implement my_app profile --design ./mockups/profile.webp
```

Revert an implementation:

```bash
mv lib/features/auth/presentation/screens/auth_screen.dart.bak \
   lib/features/auth/presentation/screens/auth_screen.dart
```

---

### 4.9 `sm --help` / `sm --version`

```bash
sm --help       # or: sm -h
sm --version    # or: sm -v
```

---

## 5. Generated Project Structure

After `sm init my_app` + `sm make feature my_app auth` + `sm make api my_app`:

```
my_app/
├── .sm_cli_config                # {"state_management": "Riverpod"}
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/
│   │   ├── network/              # from `sm make api`
│   │   │   ├── dio_client.dart
│   │   │   ├── api_endpoints.dart
│   │   │   ├── response_wrapper.dart
│   │   │   ├── network_exceptions.dart
│   │   │   └── interceptors/logging_interceptor.dart
│   │   ├── routes/
│   │   │   ├── app_router.dart   # auto-mutated by `sm make feature`
│   │   │   └── app_routes.dart   # auto-mutated by `sm make feature`
│   │   ├── theme/
│   │   │   └── app_theme.dart    # Material 3 + Google Fonts (optional)
│   │   └── utils/
│   ├── features/
│   │   └── auth/
│   │       ├── data/…
│   │       ├── domain/…
│   │       └── presentation/…
│   └── shared/
└── design/                       # populated by `sm ai` / `sm ai implement`
    ├── README.md
    ├── manifest.json
    └── *.png / *.jpg / *.webp
```

---

## 6. State Management Options

| | Riverpod | Bloc | GetX | Provider |
|---|---|---|---|---|
| Flag | `--riverpod` / `-r` | `--bloc` / `-b` | `--getx` / `-g` | `--provider` / `-p` |
| State folder | `providers/` | `bloc/` | `controllers/` + `bindings/` + `views/` | `providers/` |
| Files per feature | `_provider.dart` | `_bloc.dart`, `_event.dart`, `_state.dart` | `_controller.dart`, `_binding.dart`, `_view.dart` | `_provider.dart` |
| Packages added | `flutter_riverpod`, `dio` | `flutter_bloc`, `equatable`, `dio` | `get`, `dio` | `provider`, `dio` |
| `main.dart` wrapper | `ProviderScope` | plain `MaterialApp.router` | `GetMaterialApp` | plain `MaterialApp.router` |

The choice is stored in `.sm_cli_config` and reused by every later command. To switch, delete the file and re-run `sm init` (destructive) or edit it by hand.

---

## 7. AI Providers & Credentials

### Supported providers

| Provider | ID | Default model | Env var | Vision |
|----------|----|--------------|---------|--------|
| Anthropic Claude | `claude` | `claude-sonnet-4-6` | `ANTHROPIC_API_KEY` | ✅ |
| OpenAI ChatGPT | `openai` | `gpt-4o-mini` | `OPENAI_API_KEY` | ✅ |
| Google Gemini | `gemini` | `gemini-2.5-flash` | `GEMINI_API_KEY` | ✅ |
| xAI Grok | `grok` | `grok-3-mini` | `XAI_API_KEY` | ❌ text only |

For design-driven workflows (`sm ai --design`, `sm ai implement`), pick a vision-capable provider.

### Credential resolution order

For every AI call, the CLI resolves keys in this order:

1. **Environment variable** (e.g. `ANTHROPIC_API_KEY=…`) — highest priority.
2. **Stored credentials** at `~/.sm_cli/credentials.json`.
3. **Interactive prompt** — masked input; saved automatically after the first successful call.

### Credentials file

Location: `~/.sm_cli/credentials.json` (chmod 600 on macOS/Linux).

Shape:

```json
{
  "default_provider": "claude",
  "claude": {
    "api_key": "sk-ant-…",
    "model": "claude-sonnet-4-6"
  },
  "openai": {
    "api_key": "sk-…",
    "model": "gpt-4o"
  },
  "figma_token": "figd_…"
}
```

- `model` is optional; omit it to fall back to the provider default.
- `figma_token` lives at the top level (see §8).
- `default_provider` is used when a command doesn't specify one.

### Adding a model

```bash
sm ai config                    # → "Change model for a provider"
```
or edit the JSON directly (any provider you already have a key for).

---

## 8. Figma Integration

### Get your Figma token

1. Figma → **Settings → Personal access tokens → Create new**.
2. Copy the token (starts with `figd_`).

### Provide the token (any of these)

- Env var: `export FIGMA_TOKEN=figd_…`
- Store it: run `sm ai … --figma …`; the CLI prompts once and saves it in `~/.sm_cli/credentials.json`.
- Edit the credentials file by hand:
  ```json
  { "figma_token": "figd_…" }
  ```

### Get your Figma file key

From a URL like `https://www.figma.com/file/abcXYZ123/My-App` the key is `abcXYZ123`.

### Auto-discovery vs. explicit nodes

- `--figma <key>` alone → walks all pages, picks FRAME / COMPONENT / COMPONENT_SET nodes as reference frames.
- Add `--figma-node <id>` (repeatable) to pin specific frames. Both URL-style (`1-23`) and API-style (`1:23`) IDs work.

### Batching & rate limits

- Frames are rendered **5 per request** to avoid 400s.
- On `429 Rate Limit`, the CLI auto-backs off (5s → 15s → 30s) and honors the `Retry-After` header. If the quota is exhausted for more than 10 minutes, it prints a clear message and stops.

### Examples

```bash
sm ai my_app --figma abcXYZ123
sm ai my_app --figma abcXYZ123 --figma-node 1-23 --figma-node 4-56
sm ai my_app --figma abcXYZ123 --auto-implement
```

More detail lives in `docs/FIGMA.md`.

---

## 9. The `manifest.json` Contract

Located at `<project>/design/manifest.json`. Written by `sm ai`, optionally read from your design folder to override the AI's mapping.

**Schema**

```json
{
  "features": {
    "auth": "login.png",
    "home": "home_feed.png"
  },
  "unmapped": [
    "onboarding_background.png"
  ]
}
```

- `features`: map of `<feature_name>` → `<image_filename>`. Feature names must be snake_case; invalid entries are skipped with a warning.
- `unmapped`: files copied into `design/` but not assigned to a feature.

**Why you might edit it**

- Force a specific feature-to-design pairing before running `sm ai --auto-implement`.
- Rename a mockup without losing the mapping.
- Add designs you want copied into the project but not implemented.

---

## 10. End-to-End Workflows

### A. Solo dev, plain scaffold

```bash
sm init my_app --riverpod
sm make feature my_app auth home profile
sm make api my_app
cd my_app && flutter run
```

### B. Design-driven build from local mockups

```bash
sm ai my_app --design ./mockups --auto-implement
cd my_app && flutter run
```

The CLI plans features from your mockups, scaffolds them, and rebuilds each screen against its design.

### C. Design-driven build from Figma

```bash
export FIGMA_TOKEN=figd_…
sm ai my_app --figma abcXYZ123 --auto-implement
```

### D. Augment an existing SM CLI project

```bash
sm ai my_app --design ./new_screens
```

The questionnaire is skipped; state management is read from `.sm_cli_config`. Only new features are added; existing ones are left alone.

### E. Iterating on a single screen

```bash
sm ai implement my_app auth --design ./mockups/new_login.png
# review the diff, tweak, or revert with:
mv lib/features/auth/presentation/screens/auth_screen.dart.bak \
   lib/features/auth/presentation/screens/auth_screen.dart
```

### F. Removing a feature cleanly

```bash
sm remove feature my_app old_dashboard --force
```

---

## 11. Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| `.sm_cli_config` | `<project>/.sm_cli_config` | Stores the chosen state management for this project |
| `credentials.json` | `~/.sm_cli/credentials.json` | AI provider keys, default provider, Figma token (chmod 600) |
| `manifest.json` | `<project>/design/manifest.json` | Feature-to-design mapping (see §9) |

### `.sm_cli_config` example

```json
{
  "state_management": "Riverpod"
}
```

Falls back to `Riverpod` if missing or unreadable. Safe to hand-edit if you know what you're doing.

---

## 12. Troubleshooting

### `sm: command not found`
Add Dart's global bin to your PATH:
```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

### `❌ Project 'xxx' not found`
`sm` expects `<project>/lib` to exist. Run from the parent directory, or make sure the project was created by `sm init` (or Flutter).

### `❌ Invalid feature name`
Feature names must be snake_case: `^[a-z][a-z0-9_]*$`. Use `user_profile`, not `UserProfile` or `user-profile`.

### `⚠️ Feature "x" already exists!`
Delete it first with `sm remove feature <project> <feature>`, or pick a new name.

### Figma returned 429 or 400
- 429: the CLI backs off automatically. If it gives up, wait for the printed retry window and re-run.
- 400 on very large files: try passing `--figma-node` with a subset of frames.

### AI call fails on large mockup sets
The planner caps at 12 images / 8 MB per call and up to 4 passes (48 images total). If you're above that, cluster your mockups by prefix (e.g. `login.png`, `login-1.png`) so the CLI can auto-dedupe.

### Screen looks nothing like the design after `sm ai implement`
- Confirm you used a vision-capable provider (Claude / OpenAI / Gemini, not Grok).
- Try a different model (e.g. `claude-sonnet-4-6` or `gpt-4o`).
- Restore the backup and retry: `mv <file>.bak <file>`.

### `sm ai implement` added a package I didn't want
The CLI runs `flutter pub add` for any imported package that exists on pub.dev. Remove it with:
```bash
flutter pub remove <package>
```

---

## 13. FAQ

**Can I mix state-management libraries in one project?**
Not officially. `.sm_cli_config` holds one choice, and generators branch on it. If you need multiple, edit files manually — the CLI won't stop you.

**Does `sm ai` cost money?**
Yes — it calls the LLM provider you configured. Keep an eye on Claude / OpenAI / Gemini / Grok pricing. Local design files use fewer tokens than large Figma renders.

**Where are my API keys stored?**
`~/.sm_cli/credentials.json`, chmod 600 on macOS/Linux. Never committed to git.

**Can I use SM CLI in CI?**
Yes for `sm init`, `sm make …`, `sm remove …`, `sm list`. AI commands need a provider key in an env var (`ANTHROPIC_API_KEY`, etc.) and will fail if none is set and no prompt is possible.

**How do I upgrade?**
```bash
dart pub global activate sm_cli
```

**Can I customize the templates?**
Not without forking. Templates are inline Dart strings in `lib/generators/*.dart`. PRs welcome.

**What's the difference between `sm ai` and `sm ai implement`?**
`sm ai` plans and scaffolds a whole project. `sm ai implement` rewrites one screen against one design. `sm ai --auto-implement` chains them.

---

## Appendix: Cheat Sheet

```bash
# AI planner
sm ai <project> [--design PATH]... [--figma KEY] [--figma-node ID]... [--auto-implement]
sm ai implement <project> <feature> --design PATH

# Credentials
sm ai config
sm ai config --list
sm ai config --reset

# Meta
sm --help
sm --version
```

**Environment variables**

```bash
export ANTHROPIC_API_KEY=sk-ant-…
export OPENAI_API_KEY=sk-…
export GEMINI_API_KEY=…
export XAI_API_KEY=…
export FIGMA_TOKEN=figd_…
```

---

Questions, bugs, feature requests → https://github.com/flutterbysunny/sm_cli/issues
