# Local Android permission fix

Copied from `on_audio_query_plus_android` 1.3.0, with its original LICENSE.
The application's `pubspec.yaml` selects this copy using a path override.

`PermissionController.kt` requests and checks only `READ_MEDIA_AUDIO` on
Android 13 and later. Upstream also required `READ_MEDIA_IMAGES`, which made
audio permission checks fail in this app even after audio access was granted.
The older Android permission list is unchanged.

The retry rationale check iterates over the permission list so it also works
with a single permission, without accessing a nonexistent second element.

After modifying this native plugin, stop the app and rebuild with `flutter run`;
hot reload and hot restart do not rebuild Kotlin code.
