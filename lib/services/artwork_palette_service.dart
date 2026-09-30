import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

class SongVisuals {
  final Uint8List? artwork;
  final ColorScheme scheme;

  const SongVisuals({
    required this.artwork,
    required this.scheme,
  });
}

class ArtworkPaletteService {
  ArtworkPaletteService._();

  static final shared = ArtworkPaletteService._();

  static final fallbackScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7189B8),
    brightness: Brightness.dark,
  );

  static const _cacheLimit = 48;
  static const _concurrentLimit = 3;

  final _query = OnAudioQuery();

  final _cache = LinkedHashMap<int, SongVisuals>();
  final _inFlight = <int, Future<SongVisuals>>{};
  final _pending = <_VisualJob>[];

  int _active = 0;

  SongVisuals? peek(int songId) {
    final cached = _cache.remove(songId);

    if (cached != null) {
      _cache[songId] = cached;
    }

    return cached;
  }

  Future<SongVisuals> load(
    int songId, {
    bool priority = true,
  }) {
    final cached = peek(songId);

    if (cached != null) {
      return Future<SongVisuals>.value(cached);
    }

    final existing = _inFlight[songId];

    if (existing != null) {
      if (priority) {
        final index = _pending.indexWhere(
          (job) => job.songId == songId,
        );

        if (index > 0) {
          final job = _pending.removeAt(index);
          _pending.insert(0, job);
        }
      }

      return existing;
    }

    final job = _VisualJob(songId);
    _inFlight[songId] = job.completer.future;

    if (priority) {
      _pending.insert(0, job);
    } else {
      _pending.add(job);
    }

    _pump();
    return job.completer.future;
  }

  void preload(int songId) {
    unawaited(load(songId, priority: false));
  }

  void _pump() {
    while (_active < _concurrentLimit && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_VisualJob job) async {
    Uint8List? artwork;
    SongVisuals result;

    try {
      artwork = await _query.queryArtwork(
        job.songId,
        ArtworkType.AUDIO,
        size: 800,
        quality: 90,
      );

      if (artwork != null && artwork.isEmpty) {
        artwork = null;
      }

      var scheme = fallbackScheme;

      if (artwork != null) {
        scheme = await ColorScheme.fromImageProvider(
          provider: ResizeImage(
            MemoryImage(artwork),
            width: 96,
            height: 96,
          ),
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        );
      }

      result = SongVisuals(
        artwork: artwork,
        scheme: scheme,
      );

      _cache[job.songId] = result;

      while (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
    } catch (error) {
      debugPrint(
        'Artwork/palette loading failed for ${job.songId}: $error',
      );

      result = SongVisuals(
        artwork: artwork,
        scheme: fallbackScheme,
      );
    }

    _inFlight.remove(job.songId);
    _active--;

    job.completer.complete(result);
    _pump();
  }
}

class _VisualJob {
  final int songId;
  final Completer<SongVisuals> completer = Completer<SongVisuals>();

  _VisualJob(this.songId);
}