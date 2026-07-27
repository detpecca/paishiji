# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Note: the repo root also contains the original Chinese build spec (the "技术实施文档" that drove Task 0–8). That document is the authoritative product spec; this file is the operational guide for navigating the codebase day-to-day. When they disagree on intent, the spec wins; when this file describes *how the code is actually wired today*, this file wins.

## Project

「拍食记」— a pure-mobile personal diet-logging app (Android-priority Flutter). The user photographs a meal plate, a paid vision LLM identifies food / estimates calories & macros, and a traffic-light engine (🟢/🟡/🔴) recommends based on cut/maintain/gain goals. **No server, no account, no cloud sync** — everything is on-device. The only external dependencies are Aliyun DashScope (primary vision LLM), Zhipu GLM-4V (fallback vision LLM), and Open Food Facts (free, no key, barcode lookup). Images go to the LLM as base64-inline `data:image/jpeg;base64,...` URLs; there is no object storage.

All 9 build tasks (Task 0–8) are complete and committed on `main` at GitHub (`detpecca/paishiji`), CI green. A post-Task-8 feature adds a configurable **custom OpenAI-compatible provider** (Kimi / Doubao / Volcengine / etc.) — see "The three LLM provider abstractions" below.

## Hard constraints (red lines — violating these is rework)

1. **Every calorie number shown in the UI must carry an "估算" (estimated) badge** — `EstimatedBadge` lives in `lib/features/onboarding/onboarding_flow.dart` and is re-exported so home/recognition/barcode/diary pages all reuse it.
2. **Every LLM call must go through a Provider abstraction** (`VisionProvider` / `NutritionLabelProvider` / `NutritionEstimateProvider`), each with timeout (20s), a failover chain, and a Mock implementation. **Tests must make zero real API calls** — all tests inject `Mock*` providers. The custom OpenAI-compatible provider also goes through this abstraction (it's just another concrete `with OpenAICompatibleProvider` class).
3. **No feature that requires a server / account / cloud sync.** Reject such requests and tag `TODO(out-of-scope)`.
4. **Every local data table has a `created_at` column.** See `lib/data/db/tables.dart`.

API keys live in `flutter_secure_storage` (via the `KeyVault` abstraction), never plaintext `SharedPreferences`. The custom provider's three fields (baseUrl + model + apiKey) are stored as a JSON string under `ApiKeyType.custom`.

## Commands

The Flutter toolchain lives at `D:\Tools\flutter`; a corporate proxy (`proxy.xfusion.com:8080`) is required for all public-internet access. **Source the env script first in every shell session:**

```bash
source /d/workspace/paishiji/.claude/env.sh
```

Then standard Flutter commands work:

```bash
flutter pub get
flutter analyze                                   # must be zero warnings (CI fails otherwise)
dart format --output=none --set-exit-if-changed . # CI checks formatting — run `dart format .` before committing
flutter test                                      # full suite (196 tests, all Mock)
flutter test test/domain/traffic_light_engine_test.dart        # single test file
flutter test --plain-name "减脂"                               # single test by name substring
```

### Drift codegen

Drift tables/DAOs generate `*.g.dart`. Regenerate after touching `lib/data/db/tables.dart` or any `@DriftAccessor`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The generated files are excluded from analysis (`analysis_options.yaml` excludes `**/*.g.dart`) but ARE committed — they don't need to be regenerated on a fresh clone unless you change the schema.

### Recognition smoke test

There is a `tool/recognition_smoke.dart` facade, but on Windows `dart run` hits an sqlite3 FFI compile bug, so the smoke runs as a Flutter test:

```bash
# Mock mode (default — zero real API, no fixtures needed)
flutter test test/smoke/recognition_smoke_test.dart

# Real mode (needs a real key + 10 meal photos in test/fixtures/, which are gitignored)
PAISHIJI_SMOKE_REAL=1 DASHSCOPE_API_KEY=sk-xxx flutter test test/smoke/recognition_smoke_test.dart
```

### Android release APK build (on THIS corp-locked machine)

This build only succeeds with environment fixes applied (see "Build environment gotchas" for why):

```bash
source /d/workspace/paishiji/.claude/env.sh
mkdir -p /c/paishiji-tmp            # once
export TEMP="C:/paishiji-tmp"
export TMP="C:/paishiji-tmp"
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Release signing config is in `android/app/build.gradle.kts` (reads `android/key.properties`, which is gitignored alongside `android/app/paishiji-release.jks`).

> ⚠️ **On this machine, the built APK cannot leave.** The corp security policy blocks all outbound file transfer (USB, network drive, webmail attachment), and the corp proxy blocks GitHub release asset uploads (POST blocked, even 97 KB rejected — only PUT passes). So building here is only useful for local testing; to get the APK onto a phone, build on a different machine that can reach the open internet. See "Building on a fresh machine (no dev environment)" below.

### Building on a fresh machine (no dev environment)

Use this when building on a machine other than this corp-locked one (e.g. a personal machine on an open network). The corp machine's APK cannot be exported, so a fresh-machine build is the only path to a phone-installable APK.

**Pinned versions — copy exactly, do not upgrade (these avoid the AGP/Kotlin/JBR pitfalls documented in "Build environment gotchas"):**

| Component | Version | How |
|---|---|---|
| Flutter SDK | **3.44.8 stable** | Download `flutter_windows_3.44.8-stable.zip` (or mac/linux equivalent), unzip to a path with no spaces/CJK, add `bin` to PATH |
| Java | **17** | Microsoft OpenJDK 17, or Android Studio's bundled JBR |
| Android SDK | compileSdk 36 + build-tools 36 | Install Android Studio (easiest — also sets up the SDK) |
| AGP | 8.9.1 | Already pinned in `android/settings.gradle.kts`, no manual setup |
| Kotlin | 2.1.0 | Already pinned in `android/settings.gradle.kts`, no manual setup |

```bash
flutter --version    # confirm 3.44.8
java -version        # confirm 17+
```

**Step 1 — clone + dependencies + codegen:**

```bash
git clone https://github.com/detpecca/paishiji.git
cd paishiji
flutter pub get

# CRITICAL: *.g.dart is gitignored and NOT in the repo. A fresh clone has no
# ProfilesCompanion / FoodsCompanion etc. Without this step, build fails with
# "Undefined class 'ProfilesCompanion'" (this is the same step CI runs).
dart run build_runner build --delete-conflicting-outputs
```

**Step 2 — generate a release keystore** (the corp machine's `paishiji-release.jks` + `key.properties` are gitignored and unreachable; generate a fresh one on this machine. Self-use app — signature mismatch with any future build is fine):

```bash
keytool -genkey -v -keystore android/app/paishiji-release.jks \
  -alias paishiji -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass paishiji123456 -keypass paishiji123456 \
  -dname "CN=paishiji-dev"

cat > android/key.properties <<EOF
storePassword=paishiji123456
keyPassword=paishiji123456
keyAlias=paishiji
storeFile=paishiji-release.jks
EOF
```

**Step 3 — build:**

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk (~77 MB)
```

If on **Windows** and you hit `Unable to establish loopback connection` (JBR 21's 8.3-short-name TEMP bug, see "Build environment gotchas"):

```bash
mkdir C:\paishiji-tmp
set TEMP=C:\paishiji-tmp
set TMP=C:\paishiji-tmp
flutter build apk --release
```

(Mac/Linux do not hit this bug.)

**Step 4 — install to phone:**

```bash
# Phone: enable USB debugging (Settings → About → tap Build Number 7× →
#        Developer Options → USB debugging). USB-connect, allow debugging.
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or just copy the APK file to the phone (this machine has no corp egress filter, so USB/network drive/webmail all work) and tap-install.

**Step 5 (optional) — upload APK to the GitHub release page** (this is impossible from the corp machine because the proxy blocks POST, but works from an open-network machine). The `v1.0.0` release (id `360228826`) already exists but has no APK asset:

```bash
curl -X POST \
  -H "Authorization: token <your-PAT-with-repo-scope>" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @build/app/outputs/flutter-apk/app-release.apk \
  "https://uploads.github.com/repos/detpecca/paishiji/releases/360228826/assets?name=paishiji-v1.0.0-release.apk"
```

Once uploaded, any machine can download the APK directly from https://github.com/detpecca/paishiji/releases/tag/v1.0.0 — no build needed thereafter.

**Do NOT route this machine through the corp proxy** (`proxy.xfusion.com:8080`). Use a home network or phone hotspot. The corp proxy blocks: SDK downloads, pub/Gradle distribution fetch, and release-asset uploads (POST blocked). The whole point of using a fresh machine is that it's not behind that filter.

## Architecture

### Layering (enforced by import discipline)

```
lib/
  core/        router, theme, constants, app_exceptions, app_services, date_key
  domain/      pure Dart, NO Flutter import — 100% unit tested
                 tdee_calculator, nutrition_matcher, traffic_light_engine
  data/        Drift DB + providers (HTTP/LLM/barcode/backup/stats) + DataScope facade
  features/    UI pages + their ChangeNotifier view-models
```

`domain/` must not depend on Flutter or Drift — it works against plain in-memory types (`FoodRecord`, `DailyContext`, `FoodNutrition`). `data/` projects Drift rows into those domain types so the engine stays pure and testable.

### Dependency injection: two parallel mechanisms

1. **Riverpod `FutureProvider`** (`lib/main.dart` `appServicesProvider`) constructs the production `AppServices` with `SecureStorageKeyVault` + `HttpConnectionTester` + real `AppDatabase`. Tests override this provider with memory/Mock implementations.
2. **`AppServicesScope` (InheritedWidget, defined in `lib/features/home/home_page.dart`)** carries `AppServices` down the widget tree. `main.dart` wraps `MaterialApp.router(builder:)` with it. Pages reach services via `AppServicesScope.of(context)`.

**Riverpod 3.3.2 removed `ChangeNotifierProvider`** — so view-models (`HomeView`, `OnboardingController`, `RecognitionDraft`, `EditableItem`) use native `ChangeNotifier` / `ValueNotifier`, and the UI binds them with `ListenableBuilder` (NOT `ValueListenableBuilder<T>` — `ChangeNotifier` is not a `ValueListenable<T>`).

### Routing & app state

`lib/core/router.dart` `AppRouter` builds a `GoRouter` whose `redirect` reads `AppServices` state: no profile → `/onboarding`, has profile on onboarding → `/`. `refreshListenable: services` makes the router re-evaluate when `hasProfile` / `hasDashScopeKey` flip. `AppServices` is itself a `ChangeNotifier` for this reason.

The capture page reads `services.hasVisionKey` (DashScope OR custom-complete): no key → a friendly guidance screen (not an error). This is the only "no key" path — the app never crashes on missing keys.

### Data layer: `DataScope` facade

`lib/data/data.dart` `DataScope` wraps `AppDatabase` + the 5 DAOs and is the ONLY type `features/` imports from `data/` (it `export`s the DAOs/tables/database barrel). `ensureSeeded` imports `assets/seed_foods.json` on first launch, gated by a `kv` flag (`seed_version`) so repeat launches don't double-import — idempotent by `foods.name` UNIQUE. `homeView` is a lazily-created singleton view-model on the scope.

### The three LLM provider abstractions (all parallel, all Mock-first)

| Abstraction | File | Purpose | Mock |
|---|---|---|---|
| `VisionProvider` | `vision_provider.dart` | meal-plate → `List<VisionItem>` (name/confidence/grams/ingredients); `VisionChain` primary→fallback | `MockVisionProvider` |
| `NutritionLabelProvider` | `nutrition_label_provider.dart` | nutrition-facts photo → `LabelNutrition` (per-100g) for barcode supplement (source=3) | `MockLabelProvider` |
| `NutritionEstimateProvider` | `nutrition_estimate_provider.dart` | unmatched dish → per-100g estimate, ingest source=2 verified=0 | `MockEstimateProvider` |

Each has `Qwen*` + `Glm*` real implementations and a `Mock*` const-constructible one. **Plus each has a `Custom*` implementation** (`CustomVisionProvider` / `CustomLabelProvider` / `CustomEstimateProvider`) that reads baseUrl/model/apiKey from a user-supplied `CustomProviderConfig`. All three Qwen/GLM/Custom variants share a single `OpenAICompatibleProvider` mixin (`openai_compatible_provider.dart`) that holds the dio POST + response extraction + error mapping — adding a new vendor is a config change, not a code change. JSON parsing is tolerant (strips code fences, extracts the first `[..]` or `{..}`). `InvalidKeyException` does NOT trigger failover (a bad key is a bad key regardless of provider).

### Provider wiring & failover order

`AppServices` (in `lib/core/app_services.dart`) pre-parses the keys on `bootstrap()` / `onKeyChanged()` and constructs the failover chain in this priority: **custom (if complete) → DashScope → GLM → null (router falls back to Mock, offline-safe)**. The cached `VisionProvider` / `NutritionLabelProvider` / `NutritionEstimateProvider` instances are exposed via `cachedVision` / `cachedLabel` / `cachedEstimate` getters so the router builder (synchronous) can read them without awaiting key reads. `hasVisionKey` (DashScope OR custom-complete) gates the capture page.

### Recognition pipeline (`recognition_pipeline.dart`)

The orchestrator: compress image → `VisionProvider.analyze` → `NutritionMatcher.match` (exact name → aliases → Levenshtein ≥0.6 → notFound) → `TrafficLightEngine.evaluate` → write `recognitions` + `recognition_items`. On miss, if `estimateProvider` is injected it calls the LLM and ingests `source=2 verified=0`; otherwise it falls back to nutrition-0 (kept so the Task-4 smoke still passes without an estimator). An injected `StatsService` increments the monthly recognition count.

### Barcode flow (`barcode_flow.dart` + `barcode_page.dart`)

Three-tier lookup: local `foodsDao.findByBarcode` (re-scan hits cache, `fromCache=true`) → `OpenFoodFactsClient.lookup` (hit → ingest `source=3`) → not found → guide user to photograph the nutrition label → `NutritionLabelProvider` parses → `upsertByBarcode`. The page uses a `sealed _LookupState` with an exhaustive `switch` (Idle/Loading/Error/NotFound/Found).

### Backup & stats (`backup_service.dart`, `stats_service.dart`)

`BackupService.export` dumps all 6 tables to JSON (schema-versioned via `kBackupSchemaVersion`), writes `last_backup_at` to kv, returns a temp-file path the UI shares via `share_plus`. `import` validates the schema version (rejects mismatches), then reverse-clears by FK order and restores preserving original IDs. `HomeView._checkBackupReminder` shows a banner when ≥7 days since last backup. `StatsService` stores monthly counts in kv (`recognition_count_YYYY-MM`) and reports `count × 0.03 ¥` estimated cost (local count, not billing).

### Traffic-light engine (`traffic_light_engine.dart`)

Pure function, priority R1→R6, hit-and-stop: allergen hit → over-budget → cut-goal high-sugar/high-fat → high-protein-low-fat → within-30%-budget → else yellow. R3 lists whichever of high-sugar / high-fat apply (not a fixed string). All thresholds are in `AppConstants` and overridable per-call so the settings page can tune them.

## Build environment gotchas (non-obvious, all hit during the build)

These are specific to this corp-locked Windows machine but worth knowing:

- **JBR 21 `WEPollSelector` loopback bug:** `Selector.open()` fails with "Unable to establish loopback connection" because the default TEMP dir is an 8.3 short name (`C:\Users\L50012~1\...`) and AF_UNIX `connect0` returns "Invalid argument". Fix: point the UDS temp dir at a plain path — `export TEMP="C:/paishiji-tmp"` (the JDK reads the `TEMP` env var in `UnixDomainSocketsUtil.getTempDir`). The `-Djdk.net.unixdomain.tmpdir=...` system property does NOT work through Gradle 9's daemon (it isn't propagated to the forked daemon JVM).
- **Corporate proxy intercepts TLS** (Xfusion Web Secure Internet Gateway CA). To let the build's HTTPS downloads trust it, import the CA once into the JBR truststore: `keytool -importcert -alias xfusion-web-secure -keystore "D:/Program Files/Android/Android Studio/jbr/lib/security/cacerts" -storepass changeit -file <xfusion-ca.pem> -noprompt`.
- **Gradle 9.1.0 distribution** may need manual install: `curl -k -x http://proxy.xfusion.com:8080` the zip into `~/.gradle/wrapper/dists/gradle-9.1.0-all/<hash>/`, unzip, `touch gradle-9.1.0-all.zip.ok`, remove the `.part` file.
- **AGP version pinning:** `file_picker 11.0.2` is incompatible with AGP 9 (`FilePickerPlugin` symbol not found) and with AGP <8.9.1 (androidx deps require ≥8.9.1). `android/settings.gradle.kts` pins AGP `8.9.1` + Kotlin `2.1.0`.
- **Kotlin incremental cache cross-drive bug:** pub cache is on `C:` and the project on `D:`; Kotlin's incremental compiler throws "different roots". `android/gradle.properties` sets `kotlin.incremental=false`.
- **`build.gradle.kts` Kotlin DSL quirks:** use top-level `import java.util.Properties` / `import java.io.FileInputStream` (fully-qualified `java.util.Properties()` triggers "Unresolved reference"); `Properties.isNotEmpty` must be called as `isNotEmpty()` (it's a function, not a property).
- **Flutter 3.44 deprecations** (`RadioListTile.groupValue/onChanged`, old `SegmentedButton` API) are suppressed via `analysis_options.yaml` `deprecated_member_use: ignore` rather than churned.

## Testing conventions

- **Mock-first everywhere.** Every external dependency (vision LLM, label LLM, estimate LLM, Open Food Facts, connection tester, key vault, image processor) has a `@visibleForTesting` `Mock*` implementation. Tests construct these directly and assert structure, never real API behavior.
- **Drift in-memory DB:** `AppDatabase.forTesting(null)` uses `NativeDatabase.memory()`. Set `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` at the top of every test that opens a DB, to silence the multi-instance warning.
- **`now` injection:** time-sensitive code (`HomeView.refresh`, `StatsService`, `BackupService`, `DateKey`) takes an injectable `now: DateTime Function()?` so tests can assert cross-day / cross-month / 7-day-reminder behavior deterministically.
- Tests that load the real `seed_foods.json` use a `_StubBundle` (`test/data/seed_loader_test.dart`) so the parser/loader stay pure and offline.

## When real API keys arrive

The app ships with providers wired from the `KeyVault` at runtime via `AppServices.cachedVision` / `cachedLabel` / `cachedEstimate` (router reads these; falls back to `Mock*` if no key configured). To go live, just fill keys in the settings page:

- **DashScope**: settings → "阿里百炼 DashScope" card → paste `sk-...` → 测试连接 → 保存. Becomes primary vision/label/estimate provider.
- **GLM**: settings → "智谱 GLM" card → paste key → 保存. Becomes fallback for vision/label.
- **Custom (Kimi etc.)**: settings → "自定义 OpenAI 兼容端点" card → fill baseUrl (`https://api.kimi.com/coding/v1`) + model (`kimi-k2.7-code`) + apiKey → 测试连接 → 保存. Becomes primary; DashScope demotes to fallback.

No business logic changes on key swap — the red lines (#1 estimated badge, #2 Provider abstraction) already guarantee the swap is a config-only change. The Mock path stays as the test/offline fallback when no key is configured.
