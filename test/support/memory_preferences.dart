import 'package:shared_preferences/shared_preferences.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, String> values = {};
  final failures = <String>{};
  final void Function(String key, String value)? onWrite;

  MemoryPreferences({this.onWrite});

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failures.isNotEmpty) throw StateError('Storage unavailable');
    onWrite?.call(key, value);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failures.isNotEmpty) throw StateError('Storage unavailable');
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
