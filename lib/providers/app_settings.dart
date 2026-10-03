import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const shortAudioKey = 'hide_short_audio_v1';
  static const restoreSessionKey = 'restore_playback_session_v1';

  final SharedPreferencesAsync _preferences;
  bool _hideShortAudio = false;
  bool _restorePlaybackSession = true;

  AppSettings({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  bool get hideShortAudio => _hideShortAudio;
  bool get restorePlaybackSession => _restorePlaybackSession;

  Future<void> load() async {
    try {
      _hideShortAudio = await _preferences.getBool(shortAudioKey) ?? false;
      _restorePlaybackSession =
          await _preferences.getBool(restoreSessionKey) ?? true;
    } catch (error) {
      debugPrint('Settings loading failed: $error');
    }
    notifyListeners();
  }

  Future<void> setHideShortAudio(bool value) async {
    if (_hideShortAudio == value) return;
    await _preferences.setBool(shortAudioKey, value);
    _hideShortAudio = value;
    notifyListeners();
  }

  Future<void> setRestorePlaybackSession(bool value) async {
    if (_restorePlaybackSession == value) return;
    await _preferences.setBool(restoreSessionKey, value);
    _restorePlaybackSession = value;
    notifyListeners();
  }
}
