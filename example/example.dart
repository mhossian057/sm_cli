/// # SM CLI — Flutter Clean Architecture Generator
///
/// `sm` scaffolds Flutter projects with a feature-based clean architecture,
/// wires up state management (Riverpod / Bloc / GetX / Provider), and can
/// plan an entire project from a few questions plus optional design
/// references (local images or Figma frames). It can also rebuild a single
/// screen from a screenshot, auto-splitting the result into reusable widgets.
///
/// Read top to bottom — the steps build on each other.
///
/// ---
///
/// ## Step 1 — Install
///
/// From pub.dev:
/// ```bash
/// dart pub global activate sm_cli
/// ```
///
/// From a local checkout (development):
/// ```bash
/// dart pub global activate --source path /Volumes/ADATA/workspace/sm_cli
/// ```
///
/// From a Git repo:
/// ```bash
/// dart pub global activate --source git <github-url>
/// ```
///
/// Confirm:
/// ```bash
/// sm --version    # → sm_cli version 1.0.10
/// sm --help
/// ```
///
/// Uninstall when done:
/// ```bash
/// dart pub global deactivate sm_cli
/// ```
///
/// ---
///
/// ## Step 2 — Create a project
///
/// Two ways. Pick one.
///
/// ### 2a. Manual scaffold (`sm init`)
///
/// Interactive — picks state management, GoRouter, and theme via prompts:
/// ```bash
/// sm init my_app
/// ```
///
/// Skip prompts with a flag:
/// ```bash
/// sm init my_app --riverpod   # or -r / -b / -g / -p
/// ```
///
/// Output tree:
/// ```
/// my_app/
///   lib/
///     core/{constants,network,routes,theme,utils}/
///     features/
///     shared/
///   design/           ← reference screenshots / Figma exports live here
///   .sm_cli_config    ← remembers your state-management choice
/// ```
///
/// ### 2b. AI-planned scaffold (`sm ai`)
///
/// Asks 5 short questions and calls Claude / OpenAI / Gemini / Grok to
/// plan features, theme tokens, fonts, and extra packages. First run
/// prompts for an API key once; stored chmod-600 at
/// `~/.sm_cli/credentials.json`.
///
/// Plain (text-only planning):
/// ```bash
/// sm ai my_app
/// ```
///
/// With local design references — single folder is scanned for images:
/// ```bash
/// sm ai my_app --design ~/Downloads/designs/
/// ```
///
/// Walks ~/Downloads/designs/ for `.png/.jpg/.jpeg/.webp`, sends each
/// image to the AI, then asks the 5 questions. Expected console output
/// and on-disk result:
///
/// ```text
/// 🖼️  3 reference design(s) attached: login.png, feed.png, profile.png
/// ✔ Project type?  · Medium (5-8 features)
/// ✔ Budget?        · Low
/// ✔ Features?      · social feed with auth and profile
/// ✔ State Mgmt     · Riverpod
/// ✔ Design brief   · dark, editorial
/// ✅ Plan ready
///
/// 📋 Proposed plan
///    Provider   : Anthropic Claude (claude-sonnet-4-6)
///    State mgmt : Riverpod
///    Features   : auth, feed, profile
///    Theme      : dark, seed #FF5722
///    Aesthetic  : editorial
///    Fonts      : Fraunces (display) / Inter (body)
///    Extra deps : shared_preferences
///    Designs    : 3 image(s) → my_app/design/
///
/// ? Generate this project? (Y/n) › yes
/// 📁 Clean Architecture folders created
/// 🎨 Theme generated
/// 📦 Adding Riverpod + Dio...
/// ✨ Feature "auth" generated
/// ✨ Feature "feed" generated
/// ✨ Feature "profile" generated
/// 📦 Adding extra packages: google_fonts, shared_preferences
/// 🖼️  Saved 3 design file(s) to my_app/design/
///
/// ✅ AI-generated project "my_app" ready with 3 feature(s).
///    cd my_app && flutter run
/// ```
///
/// On-disk result:
/// ```
/// my_app/
///   lib/
///     core/{constants,network,routes,theme,utils}/    ← scaffold
///     features/auth/{data,domain,presentation}/       ← from plan
///     features/feed/{data,domain,presentation}/
///     features/profile/{data,domain,presentation}/
///     shared/
///   design/
///     README.md
///     login.png        ← copied from ~/Downloads/designs/
///     feed.png
///     profile.png
///   .sm_cli_config     ← { "stateManagement": "Riverpod" }
///   pubspec.yaml       ← go_router, flutter_riverpod, dio, google_fonts,
///                        shared_preferences added
/// ```
///
/// Specific files (comma-separated or repeated):
/// ```bash
/// sm ai my_app --design ~/mockups/login.png,~/mockups/feed.png
/// sm ai my_app --design ~/mockups/login.png --design ~/mockups/feed.png
/// ```
///
/// From Figma (free Personal Access Token from Figma → Account Settings):
/// ```bash
/// sm ai my_app --figma <file_key>
/// sm ai my_app --figma <file_key> --figma-node 1:23 --figma-node 1:42
/// ```
///
/// Full Figma setup walkthrough, token instructions, flag reference, and
/// the rate-limit pros/cons table live in `docs/FIGMA.md`. Recommended
/// reading if `--figma` returns a 429 or you're unsure whether to use
/// `--figma` vs. exporting PNGs manually and passing `--design <folder>`.
///
/// Combine sources:
/// ```bash
/// sm ai my_app --figma <file_key> --design ~/mockups/extra.png
/// ```
///
/// Every reference image is sent to the AI **and** copied into
/// `my_app/design/` for provenance. Supported types: `.png`, `.jpg`,
/// `.jpeg`, `.webp`. Vision: Claude / OpenAI / Gemini. Grok refuses
/// images cleanly.
///
/// ---
///
/// ## Step 3 — Add a feature
///
/// One feature:
/// ```bash
/// sm make feature my_app auth
/// ```
///
/// Many at once:
/// ```bash
/// sm make feature my_app auth home profile settings
/// ```
///
/// Generates the full data / domain / presentation tree under
/// `lib/features/<name>/` and auto-wires the route in
/// `lib/core/routes/app_router.dart` + `app_routes.dart`. Feature names
/// must be `snake_case` (regex `^[a-z][a-z0-9_]*$`).
///
/// ---
///
/// ## Step 4 — Add the API layer
///
/// ```bash
/// sm make api my_app
/// ```
///
/// Adds `lib/core/network/` with a Dio client, interceptors, and an
/// `ApiException` type ready for feature data sources.
///
/// ---
///
/// ## Step 5 — Implement a screen from a design
///
/// Rebuilds a feature's screen file to match a reference screenshot,
/// using `AppTheme` tokens and state-management-aware widget patterns.
/// When the result would exceed ~150 lines, the AI splits it into
/// reusable widgets under `lib/features/<feature>/presentation/widgets/`
/// (the design skill enforces this).
///
/// ```bash
/// sm ai implement my_app auth --design design/login.png
/// ```
///
/// What happens:
/// 1. Confirms before overwriting.
/// 2. Backs up the original screen to `<file>.bak`.
/// 3. Writes the new screen + every extracted widget file.
/// 4. Copies the screenshot to `my_app/design/auth_login.png`.
///
/// Expected output tree after a complex login screen:
/// ```
/// my_app/lib/features/auth/presentation/
///   screens/auth_screen.dart                ← slim, composed
///   widgets/phone_input_field.dart          ← extracted
///   widgets/social_login_button.dart        ← extracted
///   widgets/country_dropdown.dart           ← extracted
/// ```
///
/// Verify and revert:
/// ```bash
/// cd my_app && flutter analyze
/// # didn't like it?
/// mv lib/features/auth/presentation/screens/auth_screen.dart.bak \
///    lib/features/auth/presentation/screens/auth_screen.dart
/// ```
///
/// ---
///
/// ## Step 6 — List and remove features
///
/// ```bash
/// sm list my_app
/// sm remove feature my_app auth          # asks for confirmation
/// sm remove feature my_app auth --force  # skip confirmation
/// ```
///
/// `remove feature` also reverses the route wiring it added at creation.
///
/// ---
///
/// ## Step 7 — Manage AI credentials
///
/// List configured providers (keys shown masked):
/// ```bash
/// sm ai config --list
/// ```
///
/// Wipe everything (API keys + Figma token + default provider):
/// ```bash
/// sm ai config --reset
/// ```
///
/// Environment variables override stored keys when set:
/// ```
/// ANTHROPIC_API_KEY   OPENAI_API_KEY   GEMINI_API_KEY
/// XAI_API_KEY         FIGMA_TOKEN
/// ```
///
/// ---
///
/// ## End-to-end example
///
/// ```bash
/// # 1. Plan & scaffold a shopping app from Figma frames
/// sm ai shopping_app --figma abc123XYZ
///
/// # 2. Add a wishlist feature the AI didn't include
/// sm make feature shopping_app wishlist
///
/// # 3. Rebuild the cart screen from a screenshot, auto-split into widgets
/// sm ai implement shopping_app cart --design ~/mockups/cart.png
///
/// # 4. Sanity check what you have
/// sm list shopping_app
///
/// # 5. Run it
/// cd shopping_app && flutter run
/// ```
///
/// ---
///
/// ## Quick reference
///
/// ```
/// sm init <project> [--riverpod|--bloc|--getx|--provider]
/// sm make feature <project> <feature>...
/// sm make api <project>
/// sm remove feature <project> <feature> [--force]
/// sm list <project>
/// sm ai <project> [--design <path>...] [--figma <key>] [--figma-node <id>...]
/// sm ai implement <project> <feature> --design <path>
/// sm ai config [--list|--reset]
/// sm --version | --help
/// ```
void main() {
  // SM CLI is a command-line tool. Run it from a terminal — not as a
  // Dart program. The doc comments above are the canonical usage guide.
}
