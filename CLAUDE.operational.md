# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Note: the repo root also contains the original Chinese build spec (the "技术实施文档" that drove Task 0–8). That document is the authoritative product spec; this file is the operational guide for navigating the codebase day-to-day. When they disagree on intent, the spec wins; when this file describes *how the code is actually wired today*, this file wins.

## Project

「拍食记」— a pure-mobile personal diet-logging app (Android-priority Flutter). The user photographs a meal plate, a paid vision LLM identifies food / estimates calories & macros, and a traffic-light engine (🟢/🟡/🔴) recommends based on cut/maintain/gain goals. **No server, no account, no cloud sync** — everything is on-device. The only external dependencies are Aliyun DashScope (primary vision LLM), Zhipu GLM-4V (fallback vision LLM), and Open Food Facts (free, no key, barcode lookup). Images go to the LLM as base64-inline `data:image/jpeg;base64,...` URLs; there is no object storage.

All 9 build tasks (Task 0–8) are complete and committed on `main` (local git, no remote).

## Hard constraints (red lines — violating these is rework)

1. **Every calorie number shown in the UI must carry an "估算" (estimated) badge** — `EstimatedBadge` lives in `lib/features/onboarding/onboarding_flow.dart` and is re-exported so home/recognition/barcode/diary pages all reuse it.
2. **Every LLM call must go through a Provider abstraction** (`VisionProvider` / `NutritionLabelProvider` / `NutritionEstimateProvider`), each with timeout (20s), a failover chain, and a Mock implementation. **Tests must make zero real API calls** — all tests inject `Mock*` providers.
3. **No feature that requires a server / account / cloud sync.** Reject such requests and tag `TODO(out-of-scope)`.
4. **Every local data table has a `created_at` column.** See `lib/data/db/tables.dart`.

API keys live in `flutter_secure_storage` (via the `KeyVault` abstraction), never plaintext `SharedPreferences`.

## Commands

The Flutter toolchain lives at `D:\Tools\flutter`; a corporate proxy (`proxy.xfusion.com:8080`) is required for all public-internet access. **Source the env script first in every shell session:**

```bash
source /d/workspace/paishiji/.claude/env.sh
```

Then standard Flutter commands work:

```bash
flutter pub get
flutter analyze                                   # must be zero warnings (CI fails otherwise)
dart format --set-exit-if-changed lib/ test/      # CI checks formatting
flutter test                                      # full suite (~170 tests, all Mock)
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

### Android release APK build

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

The capture page reads `services.hasDashScopeKey`: no key → a friendly guidance screen (not an error). This is the only "no key" path — the app never crashes on missing keys.

### Data layer: `DataScope` facade

`lib/data/data.dart` `DataScope` wraps `AppDatabase` + the 5 DAOs and is the ONLY type `features/` imports from `data/` (it `export`s the DAOs/tables/database barrel). `ensureSeeded` imports `assets/seed_foods.json` on first launch, gated by a `kv` flag (`seed_version`) so repeat launches don't double-import — idempotent by `foods.name` UNIQUE. `homeView` is a lazily-created singleton view-model on the scope.

### The three LLM provider abstractions (all parallel, all Mock-first)

| Abstraction | File | Purpose | Mock |
|---|---|---|---|
| `VisionProvider` | `vision_provider.dart` | meal-plate → `List<VisionItem>` (name/confidence/grams/ingredients); `VisionChain` primary→fallback | `MockVisionProvider` |
| `NutritionLabelProvider` | `nutrition_label_provider.dart` | nutrition-facts photo → `LabelNutrition` (per-100g) for barcode supplement (source=3) | `MockLabelProvider` |
| `NutritionEstimateProvider` | `nutrition_estimate_provider.dart` | unmatched dish → per-100g estimate, ingest source=2 verified=0 | `MockEstimateProvider` |

Each has `Qwen*` + `Glm*` real implementations (OpenAI-compatible dio POST, image as `data:image/jpeg;base64,...`) and a `Mock*` const-constructible one. JSON parsing is tolerant (strips code fences, extracts the first `[..]` or `{..}`). `InvalidKeyException` does NOT trigger failover (a bad key is a bad key regardless of provider).

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

The app currently ships with Mock providers wired in `router.dart` (`MockVisionProvider`) and `recognition_page.dart` (`MockEstimateProvider`). To go live: read the DashScope key from `services.keyVault` in `router.dart` and swap to `QwenVisionProvider(apiKey: key)` (+ `QwenEstimateProvider` / `QwenLabelProvider` / `HttpOpenFoodFactsClient` as appropriate). The Mock path stays as the test/offline fallback. No business logic changes — the red lines (#1 estimated badge, #2 Provider abstraction) already guarantee the swap is a one-line injection change.
