# Lumen on Android

Status of the phone port, the pinned toolchain, and what still has to be done. Anything marked
"not built here" has not been compiled or run on a device yet.

## Toolchain (pinned from current vendor docs, Oct 2026)

| Piece | Version | Why |
|---|---|---|
| Qt for Android | 6.11.x (6.11.1 at time of writing) | newest release; has the `SafeArea` API for display cutouts and gesture bars |
| Android NDK | r27c (27.2.12479018) | the one Qt 6.11 itself is built with; Qt recommends matching it |
| JDK / Gradle / AGP | 21 / 9.3.1 / 9.0.0 | what Qt 6.11 supports |
| compileSdk / targetSdk | 36 | Qt 6.11's CI level |
| FFmpeg | 9.0.1 (libavformat 63) | newest stable; **Lumen compiles and plays FLAC against it unchanged** (desktop check). 8.1.2 is the fallback |
| SQLite | latest amalgamation (3.53.x), hash-checked by the fetch script | Android's NDK has no public libsqlite |
| miniaudio | vendored | has AAudio / OpenSL ES backends |
| yt-dlp runtime | `io.github.junkfood02.youtubedl-android:library:0.18.1` | ships Python, yt-dlp and QuickJS (yt-dlp needs a JS runtime for YouTube since 2025.11.12); updates yt-dlp inside the app |
| Android Auto | Media3 `MediaLibraryService` | the current media-app route for Auto |

## What is done

- Phone UI (`qml/MobileMain.qml` and friends): bottom navigation, mini player, full-screen player,
  library tab, touch menus (bottom sheet + long press), phone layouts for the detail pages.
  Checked headlessly on a desktop build with `LUMEN_MOBILE=1` at 412x915.
- yt-dlp as a built-in extension (`src/YtdlpExtension.*`): a C++ port of `extensions/ytdlp/main.py`
  with the same commands, client fallbacks and stream check. `tests/ytdlp_parity.py` compares its helper
  logic to the Python original (30/30 cases match); search, resolve and playback were run end to end against
  the stub yt-dlp. On Android it runs yt-dlp through `YtdlpRunner` -> JNI -> `app.lumen.YtdlpBridge` (Kotlin).
- LRCLIB lyrics as a built-in extension (`src/LrclibExtension.*`), tested against `tests/mock_lrclib.py`.
- Built-in extensions are declared in `native-plugins/*/plugin.json` (embedded in the app) and switched on
  automatically on Android; yt-dlp is on by default there. `LUMEN_NATIVE_EXT=1` does the same on a desktop.
- Folder picker: Android's folder URIs are mapped to real paths (`safTreeToPath`), so the normal scanner works.
- Build files: `CMakeLists.txt` Android branch, `tools/android/build-deps.sh` (OpenSSL 3.5.9 + FFmpeg 9.0.1,
  static), `tools/android/fetch-sqlite.sh`, `android/` (manifest, `build.gradle` based on Qt 6.11.1's own
  template, `LumenActivity`, `YtdlpBridge`). The static FFmpeg flag set was checked with a host build.

- Media session and Android Auto: `android/src/app/lumen/PlaybackService.kt` (Media3 `MediaLibraryService`),
  `LumenPlayer.kt` (a Media3 player that mirrors the C++ player), `LumenBridge.kt` (state in, commands out),
  `CoverProvider.kt` (covers for the system UI and the car), and `src/AndroidMedia.cpp` (JNI side).
  The browse tree (Playlists / Albums / Artists / Songs, search, "play this id") is `src/MediaBrowse.*`, plain
  Qt code that was run on a desktop build: `LUMEN_BROWSE=cat:albums ./lumen ~/Music`, `LUMEN_SEARCH_TREE=<text>`,
  `LUMEN_BROWSE_PLAY=<id>`.

**Not built or run on Android yet**: everything under `android/`, the Android branch of `CMakeLists.txt`,
`src/AndroidMedia.cpp`, the JNI parts of `YtdlpRunner.cpp`, and the two scripts in `tools/android/` (only the
FFmpeg flags were exercised). Expect to fix small things on the first build, especially in the Kotlin files,
which I could not compile here.

## Building (Linux/macOS host)

1. Install Qt 6.11.x for Android (arm64-v8a), Android SDK API 36, NDK r27c (27.2.12479018), JDK 21.
2. `tools/android/fetch-sqlite.sh`
3. `ANDROID_NDK_ROOT=<sdk>/ndk/27.2.12479018 tools/android/build-deps.sh arm64-v8a`
4. `<Qt>/android_arm64_v8a/bin/qt-cmake -S . -B build-android -G Ninja -DANDROID_SDK_ROOT=<sdk> -DANDROID_NDK_ROOT=<ndk>`
5. `cmake --build build-android --target apk`

## What is left

1. First real build and fix-up on a device (see above), then a run in the Android Auto Desktop Head Unit.
2. **Starting from the car with the app closed.** The audio engine lives in the app process, so the media
   service can only browse and play once Lumen has been opened. With the app closed, the car sees the four
   top-level folders and nothing inside. Fixing that means running the engine headless in a Qt service
   (`QtService`) so it exists without the UI; that is a restructuring of `main.cpp` and not started.
3. YouTube sign-in: a WebView login that exports `cookies.txt` (a phone cannot read another app's cookies;
   the "cookies file" option works today if you export one yourself).
4. Tablet / landscape pass, and the 16 KB page-size check of the yt-dlp library's native libraries.

## Testing the phone UI on a desktop

    LUMEN_MOBILE=1 ./lumen ~/Music
    LUMEN_NATIVE_EXT=1 LUMEN_YTDLP=/path/to/yt-dlp ./lumen   # the built-in yt-dlp extension on a desktop
