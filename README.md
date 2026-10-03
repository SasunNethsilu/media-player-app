<p align="center">
  <img src="assets/branding/music_player_icon.png" alt="Music Player icon" width="96">
</p>

# Music Player

A local music player for Android, built with Flutter. It plays audio already stored on your device, with an artwork-led interface and no accounts or streaming.

## Install

Music Player requires **Android 7.0 (API 24) or newer**. When a release is available, download the signed APK from [GitHub Releases](https://github.com/SasunNethsilu/music-player-app/releases), install it, and grant access to audio files when prompted. Songs found on your device will appear in the library.

## Features

- **Library and Songs tabs:** Browse recently played tracks, albums, artists, and playlists, or open the full song list. Search song titles and artists, and sort by title or artist.
- **Playlists:** Create, rename, and delete playlists; add, remove, and drag to reorder their songs. Playlist artwork is assembled from its tracks.
- **Playback:** Use the mini player or Now Playing screen to control playback, shuffle, and cycle through repeat off, one, and all. Reorder, remove, or clear upcoming songs in the queue.
- **System controls:** Play, pause, skip, and go back from Android media controls, the lock screen, and compatible headset or Bluetooth controls.
- **Settings:** Rescan the local library, optionally hide audio shorter than 30 seconds, and choose whether to restore the last playback session.

The short-audio filter is off by default and never deletes files. Restored sessions reopen **paused**; the app does not automatically start playing on launch. Removing a song from a playlist or queue does not delete its audio file.

Playlists, recently played tracks, settings, and playback session data are stored locally on the device. Music Player has no account or cloud sync.

## Build from source

Install a Flutter SDK compatible with the Dart version in [`pubspec.yaml`](pubspec.yaml), then run:

```sh
flutter pub get
flutter run
```

To check the project:

```sh
flutter analyze
flutter test
```

The Android scanner uses the local `third_party/on_audio_query_plus_android` dependency override. Keep it in place when building the app.

## Build a release APK

Release builds use a private signing key configured through `android/key.properties`. Those files are intentionally ignored by Git. If you are building your own APK, follow the [Flutter Android release guide](https://docs.flutter.dev/deployment/android) to create a keystore and provide `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` in `android/key.properties`. The `storeFile` path is relative to the `android` directory.

```sh
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Keep the signing key and passwords backed up and private: future updates must use the same application ID and signing key. Before each new release, increment the version in `pubspec.yaml` and keep the version shown in `lib/screens/settings_screen.dart` in sync.
