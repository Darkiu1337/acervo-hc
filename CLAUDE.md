# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Acervo H&C is a multiplatform Flutter reader for **E-Hentai / ExHentai**, **Xlecx**, and **nhentai** (fork of JHenTai), targeting Windows, Linux, Android, iOS, and macOS. Version `1.5.1+10` (from `pubspec.yaml`), app ID `app.acervo.hc`.

## Build & dev commands

```bash
# Get dependencies
flutter pub get

# Run code generation (Drift DB, etc.) — required after editing any @DriftDatabase tables/queries
dart run build_runner build

# Run code generation in watch mode during active DB work
dart run build_runner watch --delete-conflicting-outputs

# Run app on a connected device
flutter run -t lib/src/main.dart

# Lint
flutter analyze --no-fatal-infos

# Run unit tests (see test/)
flutter test
```

The `test/` directory contains unit tests covering cross-provider identity matching, nhentai API v2 parsing, Xlecx login parsing, client-side filtering & sorting, neural upscale configuration & queue, split wide pages, tap zones, watched progress, atomic JSON persistence, full backup/merge, local favorite collections, multi-source search matching, and release update version comparison. CI runs `flutter analyze --no-fatal-infos` and `flutter test` via `.github/workflows/ci.yml`.

## Architecture

### Dependency framework: GetX
State management, routing, dependency injection, and i18n all use GetX. Widgets primarily use `GetBuilder<T>` (manual `update()`) for granular rebuilds, and `.obs` for reactive settings and service revision signals (`alreadyReadService.revision`, `localFavoriteService.revision`, `watchedProgressService.revision`).

### Lifecycle: `JHLifeCircleBean` pattern

Every singleton service and setting implements `JHLifeCircleBean` from `lib/src/service/jh_service.dart`:

- `initBean()` — async init (called before `runApp`)
- `afterBeanReady()` — post-runApp setup
- `initDependencies` — list of other beans this one needs initialized first

All beans are registered in `lifeCircleBeans` in `lib/src/main.dart` and ordered via `topologicalSort()`. **Adding a new service/setting requires inserting it into `lifeCircleBeans` with accurate `initDependencies`.** Two common mixins simplify patterns:
- `JHLifeCircleBeanErrorCatch` — wraps init/ready in try/catch with logging; subclasses override `doInitBean()` / `doAfterBeanReady()`
- `JHLifeCircleBeanWithConfigStorage` — serializes/deserializes settings to the `local_config` DB table via `applyBeanConfig()` / `getBeanConfig()`

### Multi-source provider model (`GallerySource`)

External providers reuse the core `Gallery`, reader, download, and detail pipelines without schema changes by encoding the provider in `GalleryUrl.gid` (`lib/src/model/gallery_source.dart`):
- `GallerySource.eh` — E-Hentai / ExHentai (`gid < 2_000_000_000`)
- `GallerySource.nhentai` — nhentai API v2 (`2_000_000_000 <= gid < 2_100_000_000`)
- `GallerySource.xlecx` — Xlecx (`gid >= 2_100_000_000`)

### Network layer (`lib/src/network/`)

- `EHRequest` — E-Hentai/ExHentai calls with custom Dio fork (`jiangtian616/dio@append-mode`), cookie management, caching, and domain fronting
- `XlecxRequest` — HTML/session client for `xlecx.one` with isolate HTML parsing and credential/cookie auth
- `NHentaiRequest` — Direct JSON client for `nhentai.net/api/v2/` with CDN host resolution
- `JHRequest` — Upstream JHenTai backend (cloud config sync for legacy 5 types, image hashes)
- `ArchiveBotRequest` — archive.org resolution

### Database & atomic persistence

- **Drift (SQLite)** (`lib/src/database/`): schema version 24 running in a background isolate. Global `appDb` singleton declared in `database.dart`. Re-run `dart run build_runner build` after schema changes and add a step in `MigrationStrategy.onUpgrade`.
- **Atomic JSON file store** (`lib/src/utils/atomic_json_store.dart`): off-UI-thread JSON encode/decode via `isolateService` with serialized `temp -> rename` atomic writes. Used by `AlreadyReadService` (`already_read.json`) and `LocalFavoriteService` (`local_favorites.json`), with automatic one-time migration from legacy `GetStorage` keys.

### Core services (`lib/src/service/`)

- `already_read_service.dart` — Unified 3-way Already Read list with multi-signal Tier 1 metadata matching (`gallery_identity_matcher.dart`) + background Tier 2 128-bit perceptual cover dHash deduplication (`cover_hash_util.dart`)
- `local_favorite_service.dart` — Offline local favorites with user-defined collections/folders
- `watched_progress_service.dart` — Tracks seen galleries, last anchor, and manual bookmarks on the Watched tab
- `acervo_backup_service.dart` — Full versioned local backup/restore (`acervo_hc_backup` JSON) with Merge/Replace modes, covering Already Read (with cover hashes), Local Favorites (with collections), Watched progress, safe app settings, and backward compatibility with legacy `JHenTaiConfig` files
- `release_update_service.dart` — Periodic (24h) and manual GitHub Releases update checker with semver comparison, platform asset matching, and ignore-version support
- `upscale_service.dart` & `neural_upscale_service.dart` — 2x bicubic + AMD FidelityFX CAS shader upscale and 6 local Vulkan neural models (Real-CUGAN SE/Pro, SPAN, AnimeJaNai, HFA2k, Real-ESRGAN) with async preload queue (`neural_queue.dart`)
- `gallery_download/` & `archive_download_service.dart` — Parallel download engine with resume & priority
- `external_viewer_service.dart` & `image_viewer_scanner_service.dart` — Launch galleries in external image viewers

### Pages & Routing (`lib/src/pages/`, `lib/src/routes/routes.dart`)

Pages follow the GetX `*_page.dart` / `*_logic.dart` / `*_state.dart` split. `EHPage` extends `GetPage` with `side` (`left`/`right`/`fullScreen`) for tablet/desktop split layouts. Key fork pages:
- `pages/xlecx/` & `pages/nhentai/` — Dedicated provider tabs and detail pages
- `pages/multi_search/` — Unified parallel search across E-Hentai, Xlecx, and nhentai (`Routes.multiSearch`) with cross-provider equivalence badges (`multi_search_matcher.dart`)
- `pages/already_read/` & `pages/favorite/` — Client-side search, source filters, sorting (`GalleryClientFilter`), and local favorite collections
- `pages/archive_preview/` — `.zip`/`.cbz` preview
- `pages/read/` — Unified reader with split wide pages (`spread_pages.dart`), vendored `packages/photo_view`, zoom persistence, keyboard shortcuts, and shader/neural upscale

### i18n (`lib/src/l18n/`)

Custom GetX `Translations` via `LocaleText`. Six locales are maintained (`pt_BR`, `en_US`, `zh_CN`, `zh_TW`, `ko_KR`, `ru_RU`), with `pt_BR` as the primary Acervo H&C translation. Always add new keys to all 6 locale files.
