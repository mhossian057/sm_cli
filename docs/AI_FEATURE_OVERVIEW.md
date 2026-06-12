# SM CLI — AI Feature Overview

## 1. The Pain Point

Every new Flutter project — for ourselves or for a client — starts with the
**same week of setup work** before anyone writes a line of business logic:

1. **Reading the design.** A designer hands o ver 30–80 Figma frames or a
   folder of PNG mockups. An engineer manually goes through them to figure
   out *which screens are features*, *what state belongs where*, and *what
   the brand colour palette and fonts are*.
2. **Choosing the stack.** Riverpod or Bloc? Which router? Which network
   layer? Which extra packages are actually needed and which are bloat?
3. **Setting up clean architecture.** Folder structure, theme files, route
   tables, base models, API client, interceptors. The same boilerplate for
   every project, every time.
4. **Translating designs to code.** Pixel-pushing in Flutter widget trees.
   Looking up `Theme.of(context).colorScheme.X` for the 50th time. Extracting
   buttons and inputs into reusable widgets so the screen file isn't 600
   lines long.

For a typical client engagement, **steps 1–4 absorb 5–10 days of senior
engineering time** before the team is even working on the actual product.
Multiply that by every project and you're paying a tax on every contract.

On top of that, **designs and code drift apart** the moment the project
starts. The original Figma file lives in one place, the codebase lives in
another, and a year later nobody remembers which screen came from which
mockup.

---

## 2. How We Overcame It With AI

We added two AI commands to our CLI that compress the week of setup into a
single confirm prompt — without giving up control or shipping junk code.

### The two commands

| Command | What it does |
|---|---|
| `sm ai <project>` | Scaffold a complete Flutter project from a brief + designs |
| `sm ai implement <project> <feature> --design <screenshot>` | Rewrite a single screen to match a reference design |

### The process, step by step

This is the actual pipeline we implemented. Every step solves a specific
real-world problem we hit during development — these aren't theoretical
features.

#### Step 1 — Multi-vendor, bring-your-own-key

We don't lock clients into one AI vendor. The CLI supports **four
providers** behind a single interface:

- Anthropic Claude
- OpenAI ChatGPT
- Google Gemini
- xAI Grok (text-only — used for non-visual planning)

A `CredentialService` saves the chosen key locally so the user enters it
once. The default provider is configurable. **Keys are only saved *after* a
successful API call**, so a bad paste never pollutes the credentials file.

> *Why this matters for clients:* Some clients have an existing AI vendor
> relationship or budget allocation. They can bring their own key and use
> the tool with no procurement friction.

#### Step 2 — Designs come in two ways

The user attaches references either as:

- **Local folder/files** — `--design ./mockups` (PNG, JPG, JPEG, WebP)
- **Figma frames** — `--figma-key <fileKey> --figma-node <id>`

For Figma, we built a `FigmaService` that handles real-world Figma API pain
points so the client experience stays smooth:

- Auto-batches frame renders 5 at a time (Figma 400s if you ask for too
  many at once)
- Excludes `INSTANCE` and `COMPONENT_SET` so we don't render component
  variants as if they were screens
- On `429 Rate limit exceeded`, **automatic backoff**: 5s → 15s → 30s, with
  progress printed
- Reads the `Retry-After` header — if the reset window is over 10 minutes
  (the daily image-render quota is exhausted on Pro tier), we explain the
  situation and point at the manual-export workaround instead of just
  failing

#### Step 3 — Clustering: don't pay for what we don't need

A Figma export of "the auth screens" often contains 12 variants of the same
login page — `Login.png`, `Login-1.png`, `02 Login.png`, `Login_filled.png`,
etc. Sending all of them to the AI is **wasteful (money), slow (latency),
and counterproductive (the AI sees the same screen 12 times and over-weights
it)**.

We built a filename-prefix clustering algorithm that:

- Normalises filenames (strips leading `02 ` prefixes, trailing `-1`
  suffixes, file extensions)
- Groups variants under one cluster key
- Sends **one representative per cluster** to the AI
- Prints the cluster summary so the user can see what was grouped and
  rename files if the grouping looks wrong

Example actual output:

```
🧮 Clustered 47 image(s) → 11 local cluster(s)
   • login (4 variants → Login.png)
   • signup (3 variants → Signup.png)
   • profile (5 variants → Profile.png)
```

#### Step 4 — Multi-pass planning for large design sets

Even after clustering, a real product can have 20+ distinct screens. AI
vendors have hard limits — Gemini returns `503 Deadline expired` past
~15 large images, Claude returns `400` past a payload threshold. Sending
everything in one call is not possible.

So we **split the work into batches** and run multiple API calls:

- Up to **12 images per call**, **8 MB per call** (raw — base64 encoding
  inflates by ~33%, so ~10.7 MB on the wire, safely under Gemini's 20 MB
  limit)
- Up to **4 passes total** (so the absolute ceiling is 48 images analysed)
- Beyond that, even-sampling kicks in so the cost stays bounded
- Results are **merged** across passes: feature lists and package lists are
  unioned; theme tokens are taken from the first pass (we tested averaging,
  it produces muddy colours)

Example actual output:

```
🔁 Planning across 2 pass(es) so every cluster is seen
   (18 representatives, batches of 12/6).
```

#### Step 5 — The five-question intake

After designs are loaded, the CLI asks the user five questions:

1. **Project scale** — small / medium / complex (caps feature count: 3 / 8 / 15)
2. **Budget posture** — lean (lightweight packages only) or premium (best-in-class allowed)
3. **Feature brief in plain English** — "auth with phone OTP, a feed, profile, settings"
4. **State management** — Riverpod / Bloc / GetX / Provider
5. **Design brief** — anything the AI should know that isn't visible in the mockups

These constraints feed directly into the prompt so the AI's plan is
*grounded* — it can't invent features that don't appear in the designs or
the brief.

#### Step 6 — The AI plan (and the design skill)

We don't send a naive prompt. The system prompt embeds a **design skill**
— a curated set of rules that pushes the AI toward bold, distinctive theme
choices instead of the default "Roboto + safe blue" that every AI returns
when left unprompted.

The plan response is forced into a strict JSON shape:

```json
{
  "features": ["auth", "feed", "profile"],
  "extra_packages": ["shared_preferences"],
  "theme_mode": "light",
  "seed_color": "#FF6B35",
  "visual_language": "editorial",
  "display_font": "Fraunces",
  "body_font": "Inter"
}
```

Validation happens before *anything touches disk*:

- Feature names are filtered through the same `^[a-z][a-z0-9_]*$` regex our
  generator uses, so a hallucinated invalid name can't crash the pipeline
- Duplicates are stripped
- Empty plans abort with a clear "describe features more concretely" hint

#### Step 7 — Confirm before writing

The CLI prints the full plan and asks for confirmation:

```
📋 Proposed plan
   Provider   : Google Gemini (gemini-2.5-pro)
   State mgmt : Riverpod
   Features   : auth, feed, profile, settings
   Theme      : light, seed #FF6B35
   Aesthetic  : editorial
   Fonts      : Fraunces (display) / Inter (body)
   Extra deps : shared_preferences
   Designs    : 47 image(s) → my_app/design/

? Generate this project? (Y/n)
```

**Nothing is written before this prompt.** No API key is saved. No
`flutter create` runs. The user reviews the plan and either approves or
walks away with no side effects.

#### Step 8 — Generation (reusing our existing CLI)

This is the part that makes the feature *safe*: the AI plan **does not
generate code directly**. It feeds into our existing, battle-tested CLI
generators — the same ones thousands of users have been running for months.

- `initProject` creates the project skeleton, router, theme, API layer
- `makeFeature` (once per feature) creates the clean-architecture folder
  tree (data / domain / presentation), wires up routes, and inserts the
  state-management glue
- `flutter pub add` installs all extra packages in one call

The AI decides *what* to scaffold. Our deterministic code generators decide
*how*. This is why the generated code looks like every other `sm`-generated
project — clean, predictable, and ready to extend.

#### Step 9 — Designs travel with the project

After generation, **every original design file** (not just the
representatives sent to the AI) is copied into `<project>/design/`. The
codebase now carries its own design provenance — a year from now, anyone
can open the repo and see which Figma frames it was built from.

### `sm ai implement` — designs to screens

The second command takes one screenshot and rewrites a single feature's
screen file to match it. The flow:

1. Project + feature must exist (the CLI offers to auto-scaffold the
   feature if it doesn't)
2. The current screen file, the project's `AppTheme`, and the configured
   state management are read and embedded in the prompt
3. The AI is told it **must** use `Theme.of(context).colorScheme.*` — no
   hardcoded hex colours, no inline `TextStyle(fontFamily: ...)`
4. The AI is told to **keep every file under ~150 lines** and extract
   reusable widgets into separate files when the screen gets too big
5. Before overwriting, the original is backed up to `.bak` so the change is
   reversible with one `mv` command

What this means in practice: the AI doesn't produce a 500-line "god
screen". It produces a focused screen file plus 2–5 small widget files
(e.g. `phone_input_field.dart`, `social_login_button.dart`) — the same
structure a senior engineer would write.

---

## 3. The Output — What the Client Actually Gets

Running one command — `sm ai my_app --design ./figma_exports` — produces:

### A complete, runnable Flutter project

- Clean architecture folder structure (data / domain / presentation per
  feature)
- Chosen state management wired up (Riverpod / Bloc / GetX / Provider)
- GoRouter with every feature already registered as a route
- Dio-based API layer with interceptors, response wrapper, error handling
- Material 3 theme using the AI-derived seed colour, with light + dark
  modes
- Google Fonts wired into the theme — both display and body fonts
- All extra packages installed via `flutter pub add`
- Original design files preserved in `<project>/design/`

### What that means in numbers

| Metric | Before | After |
|---|---|---|
| Time to "first runnable scaffold" | 1–3 days | ~2 minutes |
| Time to "all screens stubbed with theme + routes" | 5–10 days | ~5 minutes |
| Time to "first screen matching the design" (per screen) | 4–8 hours | ~3 minutes (`sm ai implement`) |
| Design provenance preserved in repo | No (Figma elsewhere) | Yes (in `/design`) |
| Risk of "AI mess" in the codebase | High (free-form codegen) | Low (AI plans, CLI generates) |

### Quality guardrails (the part that matters to engineering managers)

- AI output is **constrained by schema validation** — invalid feature names
  never reach disk
- AI output is **executed through our deterministic generators** — the code
  shape is the same one we ship for hand-built projects
- AI output is **reviewable before write** — the confirm prompt is a
  natural checkpoint
- AI output is **reversible** — `sm ai implement` always writes a `.bak`
- Theme colours and typography are **enforced through `AppTheme`** — no
  hardcoded values can sneak in
- Files are **capped at ~150 lines** with widget extraction — no god
  components

---

## 4. Conclusion

We took the week of grunt work at the start of every Flutter project and
collapsed it into a single AI-assisted command, **without giving up
engineering quality**. The AI handles the *judgement calls* — which
features, which packages, which colour palette, which fonts — while our
existing CLI handles the *deterministic code generation* that we already
trust.

**For our delivery team**, this means we start every new client engagement
already on day 5 of the old timeline. Senior engineers spend their time on
the actual product, not on boilerplate.

**For our clients**, this means:

- Faster time-to-prototype — a working app to react to within minutes of
  handing over the Figma file
- Tighter fidelity to their designs — the theme, fonts, and layout come# SM CLI — AI Feature Overview

## 1. The Pain Point

Every new Flutter project — for ourselves or for a client — starts with the
**same week of setup work** before anyone writes a line of business logic:

1. **Reading the design.** A designer hands o ver 30–80 Figma frames or a
   folder of PNG mockups. An engineer manually goes through them to figure
   out *which screens are features*, *what state belongs where*, and *what
   the brand colour palette and fonts are*.
2. **Choosing the stack.** Riverpod or Bloc? Which router? Which network
   layer? Which extra packages are actually needed and which are bloat?
3. **Setting up clean architecture.** Folder structure, theme files, route
   tables, base models, API client, interceptors. The same boilerplate for
   every project, every time.
4. **Translating designs to code.** Pixel-pushing in Flutter widget trees.
   Looking up `Theme.of(context).colorScheme.X` for the 50th time. Extracting
   buttons and inputs into reusable widgets so the screen file isn't 600
   lines long.

For a typical client engagement, **steps 1–4 absorb 5–10 days of senior
engineering time** before the team is even working on the actual product.
Multiply that by every project and you're paying a tax on every contract.

On top of that, **designs and code drift apart** the moment the project
starts. The original Figma file lives in one place, the codebase lives in
another, and a year later nobody remembers which screen came from which
mockup.

---

## 2. How We Overcame It With AI

We added two AI commands to our CLI that compress the week of setup into a
single confirm prompt — without giving up control or shipping junk code.

### The two commands

| Command | What it does |
|---|---|
| `sm ai <project>` | Scaffold a complete Flutter project from a brief + designs |
| `sm ai implement <project> <feature> --design <screenshot>` | Rewrite a single screen to match a reference design |

### The process, step by step

This is the actual pipeline we implemented. Every step solves a specific
real-world problem we hit during development — these aren't theoretical
features.

#### Step 1 — Multi-vendor, bring-your-own-key

We don't lock clients into one AI vendor. The CLI supports **four
providers** behind a single interface:

- Anthropic Claude
- OpenAI ChatGPT
- Google Gemini
- xAI Grok (text-only — used for non-visual planning)

A `CredentialService` saves the chosen key locally so the user enters it
once. The default provider is configurable. **Keys are only saved *after* a
successful API call**, so a bad paste never pollutes the credentials file.

> *Why this matters for clients:* Some clients have an existing AI vendor
> relationship or budget allocation. They can bring their own key and use
> the tool with no procurement friction.

#### Step 2 — Designs come in two ways

The user attaches references either as:

- **Local folder/files** — `--design ./mockups` (PNG, JPG, JPEG, WebP)
- **Figma frames** — `--figma-key <fileKey> --figma-node <id>`

For Figma, we built a `FigmaService` that handles real-world Figma API pain
points so the client experience stays smooth:

- Auto-batches frame renders 5 at a time (Figma 400s if you ask for too
  many at once)
- Excludes `INSTANCE` and `COMPONENT_SET` so we don't render component
  variants as if they were screens
- On `429 Rate limit exceeded`, **automatic backoff**: 5s → 15s → 30s, with
  progress printed
- Reads the `Retry-After` header — if the reset window is over 10 minutes
  (the daily image-render quota is exhausted on Pro tier), we explain the
  situation and point at the manual-export workaround instead of just
  failing

#### Step 3 — Clustering: don't pay for what we don't need

A Figma export of "the auth screens" often contains 12 variants of the same
login page — `Login.png`, `Login-1.png`, `02 Login.png`, `Login_filled.png`,
etc. Sending all of them to the AI is **wasteful (money), slow (latency),
and counterproductive (the AI sees the same screen 12 times and over-weights
it)**.

We built a filename-prefix clustering algorithm that:

- Normalises filenames (strips leading `02 ` prefixes, trailing `-1`
  suffixes, file extensions)
- Groups variants under one cluster key
- Sends **one representative per cluster** to the AI
- Prints the cluster summary so the user can see what was grouped and
  rename files if the grouping looks wrong

Example actual output:

```
🧮 Clustered 47 image(s) → 11 local cluster(s)
   • login (4 variants → Login.png)
   • signup (3 variants → Signup.png)
   • profile (5 variants → Profile.png)
```

#### Step 4 — Multi-pass planning for large design sets

Even after clustering, a real product can have 20+ distinct screens. AI
vendors have hard limits — Gemini returns `503 Deadline expired` past
~15 large images, Claude returns `400` past a payload threshold. Sending
everything in one call is not possible.

So we **split the work into batches** and run multiple API calls:

- Up to **12 images per call**, **8 MB per call** (raw — base64 encoding
  inflates by ~33%, so ~10.7 MB on the wire, safely under Gemini's 20 MB
  limit)
- Up to **4 passes total** (so the absolute ceiling is 48 images analysed)
- Beyond that, even-sampling kicks in so the cost stays bounded
- Results are **merged** across passes: feature lists and package lists are
  unioned; theme tokens are taken from the first pass (we tested averaging,
  it produces muddy colours)

Example actual output:

```
🔁 Planning across 2 pass(es) so every cluster is seen
   (18 representatives, batches of 12/6).
```

#### Step 5 — The five-question intake

After designs are loaded, the CLI asks the user five questions:

1. **Project scale** — small / medium / complex (caps feature count: 3 / 8 / 15)
2. **Budget posture** — lean (lightweight packages only) or premium (best-in-class allowed)
3. **Feature brief in plain English** — "auth with phone OTP, a feed, profile, settings"
4. **State management** — Riverpod / Bloc / GetX / Provider
5. **Design brief** — anything the AI should know that isn't visible in the mockups

These constraints feed directly into the prompt so the AI's plan is
*grounded* — it can't invent features that don't appear in the designs or
the brief.

#### Step 6 — The AI plan (and the design skill)

We don't send a naive prompt. The system prompt embeds a **design skill**
— a curated set of rules that pushes the AI toward bold, distinctive theme
choices instead of the default "Roboto + safe blue" that every AI returns
when left unprompted.

The plan response is forced into a strict JSON shape:

```json
{
  "features": ["auth", "feed", "profile"],
  "extra_packages": ["shared_preferences"],
  "theme_mode": "light",
  "seed_color": "#FF6B35",
  "visual_language": "editorial",
  "display_font": "Fraunces",
  "body_font": "Inter"
}
```

Validation happens before *anything touches disk*:

- Feature names are filtered through the same `^[a-z][a-z0-9_]*$` regex our
  generator uses, so a hallucinated invalid name can't crash the pipeline
- Duplicates are stripped
- Empty plans abort with a clear "describe features more concretely" hint

#### Step 7 — Confirm before writing

The CLI prints the full plan and asks for confirmation:

```
📋 Proposed plan
   Provider   : Google Gemini (gemini-2.5-pro)
   State mgmt : Riverpod
   Features   : auth, feed, profile, settings
   Theme      : light, seed #FF6B35
   Aesthetic  : editorial
   Fonts      : Fraunces (display) / Inter (body)
   Extra deps : shared_preferences
   Designs    : 47 image(s) → my_app/design/

? Generate this project? (Y/n)
```

**Nothing is written before this prompt.** No API key is saved. No
`flutter create` runs. The user reviews the plan and either approves or
walks away with no side effects.

#### Step 8 — Generation (reusing our existing CLI)

This is the part that makes the feature *safe*: the AI plan **does not
generate code directly**. It feeds into our existing, battle-tested CLI
generators — the same ones thousands of users have been running for months.

- `initProject` creates the project skeleton, router, theme, API layer
- `makeFeature` (once per feature) creates the clean-architecture folder
  tree (data / domain / presentation), wires up routes, and inserts the
  state-management glue
- `flutter pub add` installs all extra packages in one call

The AI decides *what* to scaffold. Our deterministic code generators decide
*how*. This is why the generated code looks like every other `sm`-generated
project — clean, predictable, and ready to extend.

#### Step 9 — Designs travel with the project

After generation, **every original design file** (not just the
representatives sent to the AI) is copied into `<project>/design/`. The
codebase now carries its own design provenance — a year from now, anyone
can open the repo and see which Figma frames it was built from.

### `sm ai implement` — designs to screens

The second command takes one screenshot and rewrites a single feature's
screen file to match it. The flow:

1. Project + feature must exist (the CLI offers to auto-scaffold the
   feature if it doesn't)
2. The current screen file, the project's `AppTheme`, and the configured
   state management are read and embedded in the prompt
3. The AI is told it **must** use `Theme.of(context).colorScheme.*` — no
   hardcoded hex colours, no inline `TextStyle(fontFamily: ...)`
4. The AI is told to **keep every file under ~150 lines** and extract
   reusable widgets into separate files when the screen gets too big
5. Before overwriting, the original is backed up to `.bak` so the change is
   reversible with one `mv` command

What this means in practice: the AI doesn't produce a 500-line "god
screen". It produces a focused screen file plus 2–5 small widget files
(e.g. `phone_input_field.dart`, `social_login_button.dart`) — the same
structure a senior engineer would write.

---

## 3. The Output — What the Client Actually Gets

Running one command — `sm ai my_app --design ./figma_exports` — produces:

### A complete, runnable Flutter project

- Clean architecture folder structure (data / domain / presentation per
  feature)
- Chosen state management wired up (Riverpod / Bloc / GetX / Provider)
- GoRouter with every feature already registered as a route
- Dio-based API layer with interceptors, response wrapper, error handling
- Material 3 theme using the AI-derived seed colour, with light + dark
  modes
- Google Fonts wired into the theme — both display and body fonts
- All extra packages installed via `flutter pub add`
- Original design files preserved in `<project>/design/`

### What that means in numbers

| Metric | Before | After |
|---|---|---|
| Time to "first runnable scaffold" | 1–3 days | ~2 minutes |
| Time to "all screens stubbed with theme + routes" | 5–10 days | ~5 minutes |
| Time to "first screen matching the design" (per screen) | 4–8 hours | ~3 minutes (`sm ai implement`) |
| Design provenance preserved in repo | No (Figma elsewhere) | Yes (in `/design`) |
| Risk of "AI mess" in the codebase | High (free-form codegen) | Low (AI plans, CLI generates) |

### Quality guardrails (the part that matters to engineering managers)

- AI output is **constrained by schema validation** — invalid feature names
  never reach disk
- AI output is **executed through our deterministic generators** — the code
  shape is the same one we ship for hand-built projects
- AI output is **reviewable before write** — the confirm prompt is a
  natural checkpoint
- AI output is **reversible** — `sm ai implement` always writes a `.bak`
- Theme colours and typography are **enforced through `AppTheme`** — no
  hardcoded values can sneak in
- Files are **capped at ~150 lines** with widget extraction — no god
  components

---

## 4. Conclusion

We took the week of grunt work at the start of every Flutter project and
collapsed it into a single AI-assisted command, **without giving up
engineering quality**. The AI handles the *judgement calls* — which
features, which packages, which colour palette, which fonts — while our
existing CLI handles the *deterministic code generation* that we already
trust.

**For our delivery team**, this means we start every new client engagement
already on day 5 of the old timeline. Senior engineers spend their time on
the actual product, not on boilerplate.

**For our clients**, this means:

- Faster time-to-prototype — a working app to react to within minutes of
  handing over the Figma file
- Tighter fidelity to their designs — the theme, fonts, and layout come
  directly from their mockups
- A clean codebase their own engineers can extend, with the same structure
  as any hand-built project
- Design provenance preserved in the repository forever

**For sales**, the pitch is concrete: *"We can take your Figma file today
and show you a running app tomorrow morning."*

This is built, shipping (current version 1.0.21), and battle-tested against
real-world AI vendor limits — rate limits, payload caps, image-count caps,
render timeouts — every one of those is handled in the code we've
described, not hand-waved in a roadmap.

  directly from their mockups
- A clean codebase their own engineers can extend, with the same structure
  as any hand-built project
- Design provenance preserved in the repository forever

**For sales**, the pitch is concrete: *"We can take your Figma file today
and show you a running app tomorrow morning."*

This is built, shipping (current version 1.0.21), and battle-tested against
real-world AI vendor limits — rate limits, payload caps, image-count caps,
render timeouts — every one of those is handled in the code we've
described, not hand-waved in a roadmap.

---

*For technical deep-dives, see `docs/FIGMA.md` and the source under
`lib/commands/ai_*.dart` and `lib/services/ai/`.*
