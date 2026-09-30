import 'dart:math';

import 'song.dart';

enum PlaybackRepeatMode { off, one, all }

class PlaybackSequence {
  final Random _random;
  final List<_Entry> _entries = [];
  int _index = -1;
  bool _shuffle = false;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;

  PlaybackSequence({Random? random}) : _random = random ?? Random();

  Song? get current => _index < 0 ? null : _entries[_index].song;
  Object? get currentKey => _index < 0 ? null : _entries[_index];
  List<Song> get queue =>
      List.unmodifiable(_entries.skip(_index + 1).map((entry) => entry.song));
  bool get shuffleEnabled => _shuffle;
  List<Object> get queueKeys => List.unmodifiable(_entries.skip(_index + 1));
  bool get canGoNext =>
      current != null &&
      (_index + 1 < _entries.length || repeatMode == PlaybackRepeatMode.all);

  bool start(Song song, List<Song> songs, {bool? shuffle}) {
    final index = songs.indexWhere((item) => item.id == song.id);
    if (index < 0) return false;
    _entries
      ..clear()
      ..addAll([for (var i = 0; i < songs.length; i++) _Entry(songs[i], i)]);
    _index = index;
    _shuffle = shuffle ?? _shuffle;
    if (_shuffle) _shuffleUpcoming();
    return true;
  }

  void setShuffle(bool enabled) {
    if (_shuffle == enabled) return;
    _shuffle = enabled;
    if (enabled) {
      _shuffleUpcoming();
    } else {
      final upcoming = _entries.sublist(_index + 1)
        ..sort((a, b) => a.order.compareTo(b.order));
      _entries.replaceRange(_index + 1, _entries.length, upcoming);
    }
  }

  void _shuffleUpcoming() {
    final upcoming = _entries.sublist(_index + 1)..shuffle(_random);
    _entries.replaceRange(_index + 1, _entries.length, upcoming);
  }

  bool next({bool automatic = false}) {
    if (current == null) return false;
    if (automatic && repeatMode == PlaybackRepeatMode.one) return true;
    if (_index + 1 < _entries.length) {
      _index++;
      return true;
    }
    if (repeatMode == PlaybackRepeatMode.all) {
      _index = 0;
      return true;
    }
    return false;
  }

  bool previous() {
    if (current == null) return false;
    if (_index > 0) {
      _index--;
      return true;
    }
    if (repeatMode == PlaybackRepeatMode.all) {
      _index = _entries.length - 1;
      return true;
    }
    return false;
  }

  void reorder(int oldIndex, int newIndex) {
    final count = _entries.length - _index - 1;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= count ||
        newIndex >= count) {
      return;
    }
    final entry = _entries.removeAt(_index + 1 + oldIndex);
    _entries.insert(_index + 1 + newIndex, entry);
    if (!_shuffle) _saveUpcomingOrder();
  }

  void _saveUpcomingOrder() {
    final upcoming = _entries.sublist(_index + 1);
    final orders = upcoming.map((entry) => entry.order).toList()..sort();
    for (var i = 0; i < upcoming.length; i++) {
      upcoming[i].order = orders[i];
    }
  }

  void remove(Song song) {
    final index = _entries.indexWhere(
      (entry) => entry.song.id == song.id,
      _index + 1,
    );
    if (index >= 0) _entries.removeAt(index);
  }

  void clearUpcoming() => _entries.removeRange(_index + 1, _entries.length);

  void removeEntry(Object key) {
    final index = _entries.indexWhere((entry) => identical(entry, key));
    if (index > _index) _entries.removeAt(index);
  }

  void enqueue(Song song, {required bool next}) {
    final existing = _entries.indexWhere(
      (entry) => entry.song.id == song.id,
      _index + 1,
    );
    if (existing >= 0 && !next) return;
    final entry = existing >= 0
        ? _entries.removeAt(existing)
        : _Entry(
            song,
            _entries.fold<int>(-1, (value, item) => max(value, item.order)) + 1,
          );
    if (next) {
      _entries.insert(_index + 1, entry);
      final upcoming = _entries.sublist(_index + 1)
        ..sort((a, b) => a.order.compareTo(b.order));
      final orders = upcoming.map((item) => item.order).toList()..sort();
      upcoming.remove(entry);
      upcoming.insert(0, entry);
      for (var i = 0; i < upcoming.length; i++) {
        upcoming[i].order = orders[i];
      }
    } else {
      _entries.add(entry);
    }
  }
}

class _Entry {
  final Song song;
  int order;

  _Entry(this.song, this.order);
}
