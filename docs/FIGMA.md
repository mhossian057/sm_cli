# Using Figma with `sm ai`

`sm ai my_app --figma <file_key>` lets the AI planner read directly from
your Figma file: it renders frames as PNGs (named after the frames in
Figma), sends them as multimodal references, and infers features / theme
tokens / fonts from the pixels. The planner also returns a
`feature → design.png` map, which is written to `<project>/design/manifest.json`.

Add `--auto-implement` to chain a second step: after scaffolding, `sm`
loops over the mapping and calls `sm ai implement` for every paired
feature so each screen is rebuilt from its design without further input.

Same effect can be achieved by exporting PNGs from Figma manually and
passing `--design <folder>`. **For most users that's the better path** —
Figma's image-render API has a tight daily quota that can lock you out
for days at a time. See [Pros & Cons](#pros--cons) below.

---

## Prerequisites

- `sm_cli >= 1.0.15` (older versions don't surface quota lockouts clearly).
- A Figma account on any tier — **Personal Access Tokens are free on every
  plan**, including the free Starter plan.
- The Figma file must be accessible to the account that issued the token.
  Team-locked files require a token from a team member.

---

## Step 1 — Generate a Personal Access Token

1. Sign in to [figma.com](https://figma.com).
2. Click your avatar (top-right) → **Settings**.
3. Open the **Security** tab in the left sidebar.
4. Scroll to **Personal access tokens** → **Generate new token**.
5. Configure the token:
   - **Name**: `sm_cli` (or anything memorable).
   - **Expiration**: 30 / 60 / 90 days, or no expiration. 90 days is a
     reasonable default.
   - **Scopes**: only `File content → Read` is required. You can leave
     the others off.
6. Click **Generate token**.
7. **Copy the value immediately** — Figma shows it exactly once. It looks
   like `figd_aBcDeFgHiJkLmNoPqRsTuVwXyZ123456`.

If you lose it, generate another. Old tokens can be revoked from the
same page.

---

## Step 2 — Find your file key

Open the file in Figma. The URL looks like:

```
https://www.figma.com/design/3EjicvlHjJkMDnCeQGcoMY/My-App-Mockups?node-id=10435-37784
                            └────────────────────┘                 └─────────────┘
                                  file_key                          node-id (optional)
```

- Everything between `/design/` (or `/file/` for older URLs) and the next
  `/` is your `file_key`.
- The `node-id` parameter (when you've clicked into a specific frame) is
  the node ID you'd pass to `--figma-node`. URLs use a dash (`10435-37784`),
  the API uses a colon (`10435:37784`) — `sm` normalizes either form.

---

## Step 3 — Provide the token

`sm` looks for the token in this priority order:

1. `FIGMA_TOKEN` environment variable.
2. Stored token in `~/.sm_cli/credentials.json` (written after a successful
   first run).
3. Interactive prompt (first run, if neither of the above is set).

Pick one of these three patterns:

### 3a. Interactive (easiest, first-time only)

Just run the command. `sm` prompts once, then saves the token to
`~/.sm_cli/credentials.json` (chmod 600). Future runs use the stored value
silently.

```bash
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY
# 🔑 No saved Figma token. Personal Access Tokens are free — ...
# ? Enter Figma API key › figd_xxxxxxxxxxxxxxxxxxxxx
# 🎨 Fetching Figma frames for 3EjicvlHjJkMDnCeQGcoMY...
# 🔐 Saved Figma token to /Users/you/.sm_cli/credentials.json
```

### 3b. One-shot env var (CI, or you don't want it stored on disk)

Prefix the command. Only lives for that one invocation:

```bash
FIGMA_TOKEN=figd_xxxxxxxxxxxxxxxxxxxxx \
  sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY
```

### 3c. Persistent shell export

Add to `~/.zshrc` (or `~/.bashrc` on bash):

```bash
# ~/.zshrc
export FIGMA_TOKEN="figd_xxxxxxxxxxxxxxxxxxxxx"
```

Reload your shell, then run plain commands:

```bash
source ~/.zshrc
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY   # picks up FIGMA_TOKEN silently
```

### 3d. `.env` file (manual sourcing)

`sm_cli` does **not** auto-load `.env` files. If you keep secrets there,
source them yourself:

```bash
# .env
FIGMA_TOKEN=figd_xxxxxxxxxxxxxxxxxxxxx
GEMINI_API_KEY=AIzaSy...
```

```bash
export $(grep -v '^#' .env | xargs) && sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY
```

### Rotating or removing the token

```bash
sm ai config --reset          # wipes all stored credentials (AI keys + Figma token)
unset FIGMA_TOKEN             # clear the env var in the current shell
```

---

## Step 4 — Run the command

### Render every screen in the file (auto-discovery)

```bash
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY
```

Walks every page, descends into `SECTION` containers, collects every
`FRAME` and `COMPONENT` node, renders them in batches of 5.
`INSTANCE` and `COMPONENT_SET` nodes are excluded (duplicates and
variant collections, not screens).

### Render specific frames

Click the frame(s) in Figma, copy the `node-id` from the URL, and pass:

```bash
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY --figma-node 10435-37784
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY \
  --figma-node 10435-37784 --figma-node 10794-43592
```

The dash/colon form doesn't matter — both work.

### Combine with local images

`--figma` and `--design` are additive. Use Figma for primary screens,
add an inspirational reference from your hard drive:

```bash
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY --design ~/inspiration/dribbble_card.png
```

### Implementing a single screen from a Figma frame

`sm ai implement` only accepts local files — there's no `--figma` shortcut
because the API quota is too tight for casual re-runs. The good news:
after a `sm ai my_app --figma <key>` run, every rendered frame is already
saved into `<project>/design/` with a human-readable name derived from
the Figma frame (e.g. `login_screen.png`). Use those directly:

```bash
sm ai implement my_app auth --design my_app/design/login_screen.png
```

If you'd rather re-export from Figma manually:

```bash
# In Figma: select the frame, Cmd+Shift+E → PNG → save to my_app/design/login.png
sm ai implement my_app auth --design my_app/design/login.png
```

### Auto-implement every mapped feature in one shot

```bash
sm ai my_app --figma 3EjicvlHjJkMDnCeQGcoMY --auto-implement
```

After the project is scaffolded, `sm` walks `design/manifest.json` and
calls `sm ai implement` for every `feature → design` pair. Behavior:

- **Per-feature confirmation is skipped** (you already confirmed at the
  start). Each call still backs up the original screen to `<file>.bak`.
- **Continue on failure.** A failed feature does not stop the loop. At
  the end you get a summary: `✅ N implemented, ❌ M failed (auth: …)`.
- **Retry individual failures manually**:
  ```bash
  sm ai implement my_app auth --design design/login_screen.png
  ```
- **Cost.** Each mapped feature triggers one additional AI vision call.
  A 5-feature project ≈ 1 plan call + 5 implement calls. Expect minutes
  and noticeably higher token spend — gate behind `--auto-implement` so
  the plain `--figma` path stays cheap.
- **Unmapped features.** Features the AI added from the brief (no
  matching design) are scaffolded as stubs and **skipped** by the loop.
  They appear in the `Mapping:` block of the confirmation screen as
  `<feature> → (no design)`.

---

## What lands in `<project>/design/`

Every `--figma` run writes a `design/` folder containing the rendered
PNGs plus a `manifest.json`. Example for a 4-feature plan with 5 frames
attached:

```
my_app/design/
  manifest.json
  login_screen.png      ← frame named "Login Screen" in Figma
  signup.png            ← frame named "Signup" in Figma
  home_feed.png
  user_profile.png
  settings.png
```

### Filename rules

- Frame names are sanitized to snake_case: `Login Screen` →
  `login_screen.png`.
- Collisions are deduped with `_2`, `_3` suffixes (`login_screen.png`,
  `login_screen_2.png`, …).
- If a frame is unnamed in Figma, the file falls back to
  `frame_<node_id>.png`.
- When you pass `--figma-node` explicitly, `sm` queries Figma for each
  node's name so filenames stay readable even for hand-picked frames.

### `manifest.json` shape

```json
{
  "features": {
    "auth": "login_screen.png",
    "feed": "home_feed.png",
    "profile": "user_profile.png"
  },
  "unmapped": ["signup.png", "settings.png"]
}
```

- `features` — the AI's `feature → design.png` mapping. Drives the
  `--auto-implement` loop. Empty `{}` if no designs were attached or the
  AI returned no mapping.
- `unmapped` — designs that landed on disk for provenance but weren't
  paired with a feature (e.g. duplicate screens, secondary variants, or
  frames the AI grouped under one feature).

The manifest is regenerated on every `sm ai --figma` run; edit it by
hand if you want to remap a feature to a different frame before
re-running `sm ai implement`.

### Pre-supplying your own mapping (`--design <dir>` + `manifest.json`)

You can skip the AI's auto-mapping by dropping a `manifest.json` inside
any `--design` directory. When present, the user mapping is treated as
authoritative — the AI still picks theme/fonts/aesthetic but its
`feature_to_design` output is discarded, and any feature in your manifest
that the AI didn't pick is added to the scaffold so it gets generated.

Example layout (no Figma needed):

```
designs/
  manifest.json
  Login Screen.png
  Home Feed.png
  Profile.png
```

```json
// designs/manifest.json
{
  "features": {
    "auth": "Login Screen.png",
    "feed": "Home Feed.png",
    "profile": "Profile.png"
  }
}
```

```bash
sm ai my_app --design ./designs --auto-implement
```

What the run does:
1. Loads the three PNGs as references and shows the AI all of them for
   theme/font selection.
2. Reads `designs/manifest.json` and prints
   `📝 Loaded 3 feature mapping(s) from designs/manifest.json`.
3. Confirms with `Mapping (from designs/manifest.json):` so it's
   obvious the AI's pick was replaced.
4. Scaffolds `auth`, `feed`, `profile` even if the AI's plan didn't
   include them.
5. Auto-implements each one from its paired design.

Filename matching is forgiving — the manifest can reference either the
original filename (`Login Screen.png`), the sanitized form
(`login_screen.png`), or any case-variant. Entries with no matching
file are dropped with a warning but never fatal.

Manifests in multiple `--design` directories are merged (later wins on
collision). Combining with `--figma` is allowed: the manifest overrides
mapping for files it names; figma frames not claimed by the manifest
land in `unmapped` and are saved for provenance only.

---

## All flags at a glance

| Flag | Repeatable | Purpose |
|---|---|---|
| `--figma <key>` | no | Figma file key (from the URL after `/design/`). |
| `--figma-node <id>` | yes | Specific frame(s) to render. Dash or colon form both accepted. Omit to auto-discover all screens. |
| `--design <path>` | yes | Local PNG/JPG/JPEG/WEBP file, folder, or comma-separated list. Can be combined with `--figma`. |
| `--auto-implement` | no | After scaffolding, run `sm ai implement` for every feature paired with a design in the manifest. Continues on per-feature failure and prints a summary. |

---

## Pros & Cons

| Aspect | `--figma <key>` | `--design <folder>` (manual export) |
|---|---|---|
| **Setup** | Generate one PAT, paste once. | Open Figma, `Cmd+Shift+E`, save. |
| **Re-runs** | Single command. | Re-export only if designs change. |
| **API quota** | **Hard daily quota** on `/images` — see below. | None. Files are local. |
| **Speed** | Slower — render + download (~2s per 5 frames + 800ms pause). | Instant — local file read. |
| **File access** | Requires a token that can see the file. Team files need a team member's token. | Anything you can open in Figma can be exported. |
| **Reproducibility** | Re-fetches latest pixels every run. | Snapshot at the moment of export. Add to git for full provenance. |
| **CI / automation** | Works, but burns the daily quota fast. | Trivial — drop PNGs in the repo, commit, build. |
| **Offline use** | Requires network. | Works offline. |

**Honest recommendation:** unless you're iterating live with a designer and
absolutely need fresh pixels every time, **prefer `--design <folder>`**.
Export once, commit the PNGs alongside the code, and you'll never hit
quota issues. The Figma API path is a convenience that turns into a wall
the moment you exceed the daily budget.

---

## Rate limits — the hard truth

Figma's API uses a tiered, cost-based rate limit system. Each endpoint
costs different "credits," and the `/v1/images` endpoint (the one `sm`
uses to render PNGs) is in the **most expensive tier**.

### What `sm` does to stay under the limit

- **Batches of 5** frames per `/images` request (configurable in
  `lib/services/figma_service.dart` as `_batchSize`).
- **800 ms pause** between successful batches.
- **Default scale = 1** (smaller PNGs are cheaper to render than `scale=2`).
- **Retry with backoff** on transient `429`s: 5s → 15s → 30s.
- **Reads the `Retry-After` header** on `429` and tells you the real
  reset time. If it's >10 minutes, it's a daily-quota lockout (not a
  per-minute throttle) and `sm` says so explicitly.
- **Excludes `INSTANCE` / `COMPONENT_SET`** from auto-discovery so we
  don't pay for duplicates and variant libraries.

### What `sm` cannot do

- It cannot work around a daily quota lockout. Once Figma returns
  `retry-after: 397450` (~4.5 days), there's no client-side mitigation.
- It cannot raise your account's quota. Upgrading Figma plans doesn't
  automatically lift the image-render limit (Pro accounts hit
  `x-figma-rate-limit-type: low` as easily as free ones).

### Real-world budget guidance

Rough back-of-envelope, based on Figma's behavior at time of writing
(June 2026 — exact numbers are not published and change):

| Action | Approx. cost | Notes |
|---|---|---|
| `/me` | 1 credit | Trivial. |
| `/files/<key>?depth=N` | ~5-10 credits | Used for auto-discovery. |
| `/images/<key>?ids=...` | **~50-100 credits per frame** | Scales with frame size and `scale=` parameter. |

Practical implications:

- A single `sm ai my_app --figma <key>` on a file with ~30 frames likely
  uses 1500–3000 credits.
- The "low" tier resets the budget roughly every 24 hours.
- Heavy iterative use (re-running the AI planner repeatedly) is what
  burns through the quota — not a single planning session.

### Recognizing each kind of 429

`sm` reads the `x-figma-rate-limit-type` and `retry-after` headers to
distinguish two cases:

| Symptom | Meaning | What to do |
|---|---|---|
| `retry-after` ≤ 600s | Transient per-minute throttle. | `sm` retries automatically with 5s → 15s → 30s backoff. Usually clears on its own. |
| `retry-after` > 600s | Daily quota lockout. `sm` prints the reset hours and points at `--design`. | Wait (hours/days), use a different account, or switch to manual export. |

### What you'll see when quota is exhausted

```
❌ Exception: Figma /images failed (429): {"status":429,"err":"Rate limit exceeded"}

This is a daily image-render quota lockout, NOT a transient throttle.
  • Quota tier: low
  • Reset in: ~110h

Workaround: export the frames manually from Figma
(File → Export... → PNG) and use --design <folder> instead of --figma.
Same result, no Figma API quota.
```

---

## Troubleshooting

### "Could not find an option named '--figma'"

You're running an older installed binary. Reactivate from source:

```bash
dart pub global deactivate sm_cli
dart pub global activate --source path /path/to/sm_cli
hash -r        # zsh: forget cached binary location
sm --version   # confirm 1.0.15 or later
```

### "No renderable frames found in Figma file ..."

Auto-discovery didn't find any `FRAME` / `COMPONENT` nodes. Either:
- The file has all screens inside `GROUP`s (not standard frames). Convert
  them to frames in Figma, or pass `--figma-node` explicitly.
- The file is empty / you mistyped the file key.

Open the file in Figma, click any screen, copy the `node-id` from the
URL, and pass:

```bash
sm ai my_app --figma <key> --figma-node 10435-37784
```

### "Figma /files failed (403)" or (404)

- `403`: your token doesn't have access to that file. Common with Team
  files when your PAT is from a personal account.
- `404`: wrong file key. Re-check the URL.

### "Render timeout, try requesting fewer or smaller images"

Individual frames are too large at the current scale. Either:
- Reduce the batch size (`_batchSize` in `FigmaService`).
- Target a small subset with `--figma-node`.

### "Rate limit exceeded" with `retry-after` > 10 minutes

Quota lockout. See [Rate limits](#rate-limits--the-hard-truth). Use the
manual-export path instead.
