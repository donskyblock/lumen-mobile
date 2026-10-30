cmake_minimum_required(VERSION 3.21)
project(lumen VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.4 REQUIRED COMPONENTS Quick Concurrent Network)
find_package(Threads REQUIRED)
if(NOT ANDROID)
  find_package(ZLIB REQUIRED)
endif()
if(ANDROID)
  # Static FFmpeg (+ OpenSSL for https) and the SQLite amalgamation, built per ABI by tools/android/*.sh.
  set(LUMEN_ANDROID_DEPS "${CMAKE_SOURCE_DIR}/android-deps" CACHE PATH "Where tools/android/build-deps.sh and fetch-sqlite.sh put their output")
  set(LUMEN_FFMPEG_DIR "${LUMEN_ANDROID_DEPS}/ffmpeg/${ANDROID_ABI}")
  set(LUMEN_SQLITE_DIR "${LUMEN_ANDROID_DEPS}/sqlite")
  foreach(f "${LUMEN_FFMPEG_DIR}/lib/libavformat.a" "${LUMEN_FFMPEG_DIR}/ssl/lib/libssl.a" "${LUMEN_SQLITE_DIR}/sqlite3.c")
    if(NOT EXISTS "${f}")
      message(FATAL_ERROR "Missing ${f}\nRun tools/android/build-deps.sh ${ANDROID_ABI} and tools/android/fetch-sqlite.sh first (see docs/ANDROID.md).")
    endif()
  endforeach()
elseif(WIN32)
  # vcpkg supplies these packages when using scripts/setup.ps1.
  find_package(unofficial-sqlite3 CONFIG REQUIRED)
  find_package(FFMPEG REQUIRED)
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(SQLITE REQUIRED IMPORTED_TARGET sqlite3)
  pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavformat libavcodec libswresample libavutil)
endif()

qt_add_executable(lumen
  src/main.cpp
  src/Track.h
  src/Probe.cpp            src/Probe.h
  src/Covers.cpp           src/Covers.h
  src/Palette.cpp          src/Palette.h
  src/Library.cpp          src/Library.h          src/Discovery.cpp
  src/PlayStats.h
  src/TextUtil.h
  src/Playlists.cpp        src/Playlists.h
  src/Profiles.cpp         src/Profiles.h
  src/AudioEngine.cpp      src/AudioEngine.h
  src/Db.cpp               src/Db.h
  src/Catalog.cpp          src/Catalog.h
  src/Resolver.cpp         src/Resolver.h
  src/Metadata.cpp         src/Metadata.h
  src/Presence.cpp         src/Presence.h
  src/SongIndex.cpp        src/SongIndex.h
  src/Taste.cpp            src/Taste.h
  src/SpotifyImport.cpp    src/SpotifyImport.h
  src/PluginManager.cpp    src/PluginManager.h
  src/NativeExtension.cpp  src/NativeExtension.h
  src/YtdlpExtension.cpp   src/YtdlpExtension.h
  src/YtdlpRunner.cpp      src/YtdlpRunner.h
  src/LrclibExtension.cpp  src/LrclibExtension.h
  src/MediaBrowse.cpp      src/MediaBrowse.h
  src/Lyrics.cpp           src/Lyrics.h
  src/Marketplace.cpp      src/Marketplace.h
  src/UiState.h
  src/Bus.h
  src/Player.cpp           src/Player.h
  src/Icons.cpp            src/Icons.h
  src/WavyProgress.cpp     src/WavyProgress.h
  src/miniaudio_impl.cpp
)

file(GLOB QML_FILES RELATIVE ${CMAKE_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml qml/*.js)
qt_add_resources(lumen "qml" PREFIX "/" FILES ${QML_FILES})

qt_add_resources(lumen "nativeplugins" PREFIX "/" FILES native-plugins/ytdlp/plugin.json native-plugins/lrclib/plugin.json)

target_include_directories(lumen PRIVATE third_party)
if(ANDROID)
  add_library(lumen_sqlite STATIC "${LUMEN_SQLITE_DIR}/sqlite3.c")
  target_include_directories(lumen_sqlite PUBLIC "${LUMEN_SQLITE_DIR}")
  target_compile_definitions(lumen_sqlite PRIVATE SQLITE_THREADSAFE=1 SQLITE_OMIT_LOAD_EXTENSION=1 SQLITE_OMIT_DEPRECATED=1 SQLITE_DEFAULT_MEMSTATUS=0)
  target_compile_options(lumen_sqlite PRIVATE -w)
  target_sources(lumen PRIVATE src/AndroidMedia.cpp src/AndroidMedia.h)
  target_include_directories(lumen PRIVATE "${LUMEN_FFMPEG_DIR}/include")
  # link order matters for static archives: users before providers
  target_link_libraries(lumen PRIVATE Qt6::Quick Qt6::Concurrent Qt6::Network lumen_sqlite
    "${LUMEN_FFMPEG_DIR}/lib/libavformat.a" "${LUMEN_FFMPEG_DIR}/lib/libavcodec.a" "${LUMEN_FFMPEG_DIR}/lib/libswresample.a" "${LUMEN_FFMPEG_DIR}/lib/libavutil.a"
    "${LUMEN_FFMPEG_DIR}/ssl/lib/libssl.a" "${LUMEN_FFMPEG_DIR}/ssl/lib/libcrypto.a"
    z m dl log android Threads::Threads)
  target_compile_options(lumen PRIVATE -Wall -Wextra -Wno-unused-parameter)
  set_source_files_properties(src/miniaudio_impl.cpp PROPERTIES COMPILE_OPTIONS "-w")
  # Android 15+ devices use 16 KB memory pages: every library in the APK has to be aligned for it
  target_link_options(lumen PRIVATE -Wl,-z,max-page-size=16384)
  set_target_properties(lumen PROPERTIES
    QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_SOURCE_DIR}/android"
    QT_ANDROID_MIN_SDK_VERSION 28
    QT_ANDROID_TARGET_SDK_VERSION 36
    QT_ANDROID_VERSION_NAME "${PROJECT_VERSION}"
    QT_ANDROID_VERSION_CODE 1)
elseif(WIN32)
  target_include_directories(lumen PRIVATE ${FFMPEG_INCLUDE_DIRS})
  target_link_directories(lumen PRIVATE ${FFMPEG_LIBRARY_DIRS})
  target_link_libraries(lumen PRIVATE Qt6::Quick Qt6::Concurrent Qt6::Network ${FFMPEG_LIBRARIES} unofficial::sqlite3::sqlite3 Threads::Threads ZLIB::ZLIB)
  target_compile_options(lumen PRIVATE /W4 /wd4100)
  set_source_files_properties(src/miniaudio_impl.cpp PROPERTIES COMPILE_OPTIONS "/w")
else()
  target_link_libraries(lumen PRIVATE Qt6::Quick Qt6::Concurrent Qt6::Network PkgConfig::FFMPEG PkgConfig::SQLITE Threads::Threads ZLIB::ZLIB ${CMAKE_DL_LIBS} m)
  target_compile_options(lumen PRIVATE -Wall -Wextra -Wno-unused-parameter)
  set_source_files_properties(src/miniaudio_impl.cpp PROPERTIES COMPILE_OPTIONS "-w")
endif()

include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_ok OUTPUT ipo_msg)
if(ipo_ok AND CMAKE_BUILD_TYPE STREQUAL "Release")
  set_property(TARGET lumen PROPERTY INTERPROCEDURAL_OPTIMIZATION ON)
endif()

# Bundled (official) extensions: next to the binary for dev builds, share/ when installed.
if(NOT ANDROID)
  add_custom_command(TARGET lumen POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/plugins $<TARGET_FILE_DIR:lumen>/plugins)
  install(TARGETS lumen RUNTIME DESTINATION bin)
  install(DIRECTORY plugins/ DESTINATION share/lumen/plugins USE_SOURCE_PERMISSIONS)
endif()

# Parity check of the native yt-dlp helpers against extensions/ytdlp/main.py (python3 tests/ytdlp_parity.py <binary>)
option(LUMEN_BUILD_TESTS "Build developer test helpers" OFF)
if(LUMEN_BUILD_TESTS AND NOT ANDROID)
  qt_add_executable(ytdlp_parity tests/ytdlp_parity.cpp src/YtdlpExtension.cpp src/YtdlpExtension.h src/YtdlpRunner.cpp src/YtdlpRunner.h src/NativeExtension.h)
  target_link_libraries(ytdlp_parity PRIVATE Qt6::Core Qt6::Network)
endif()
