import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/providers/app_settings.dart';
import 'package:media_player/screens/settings_screen.dart';

import 'support/memory_preferences.dart';

void main() {
  test(
    'settings keep existing defaults and persist across instances',
    () async {
      final preferences = MemoryPreferences();
      final first = AppSettings(preferences: preferences);
      addTearDown(first.dispose);
      await first.load();
      expect(first.hideShortAudio, isFalse);
      expect(first.restorePlaybackSession, isTrue);

      await first.setHideShortAudio(true);
      await first.setRestorePlaybackSession(false);

      final second = AppSettings(preferences: preferences);
      addTearDown(second.dispose);
      await second.load();
      expect(second.hideShortAudio, isTrue);
      expect(second.restorePlaybackSession, isFalse);
    },
  );

  test('failed setting writes leave the current choices intact', () async {
    final preferences = MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    addTearDown(settings.dispose);
    preferences.failures.add('storage');

    await expectLater(settings.setHideShortAudio(true), throwsStateError);
    await expectLater(
      settings.setRestorePlaybackSession(false),
      throwsStateError,
    );
    expect(settings.hideShortAudio, isFalse);
    expect(settings.restorePlaybackSession, isTrue);
  });

  test('displayed app version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (.+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
