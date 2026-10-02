import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

class SongVisuals {
  final Uint8List? artwork;
  final ColorScheme scheme;

  const SongVisuals({required this.artwork, required this.scheme});
}

class ArtworkPaletteService {
  ArtworkPaletteService._();

  static final shared = ArtworkPaletteService._();

  static final fallbackScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7189B8),
    brightness: Brightness.dark,
  );

  static const _artworkCacheLimit = 48;
  static const _paletteCacheLimit = 48;
  static const _artworkConcurrentLimit = 3;
  static const _paletteConcurrentLimit = 2;
  static const _systemArtworkFileLimit = 12;

  final _query = OnAudioQuery();

  final _artworkCache = <int, Uint8List?>{};
  final _paletteCache = <int, ColorScheme>{};
  final _artworkInFlight = <int, Future<Uint8List?>>{};
  final _paletteInFlight = <int, Future<ColorScheme>>{};
  final _pendingArtwork = <_ArtworkJob>[];
  final _pendingPalettes = <_PaletteJob>[];
  final _systemArtworkFiles = <int, File>{};
  final _systemArtworkInFlight = <int, Future<Uri?>>{};

  int _activeArtwork = 0;
  int _activePalettes = 0;

  SongVisuals? peek(int songId) {
    if (!_artworkCache.containsKey(songId)) return null;

    final scheme = _paletteCache.remove(songId);
    if (scheme == null) return null;

    final artwork = _artworkCache.remove(songId);
    _artworkCache[songId] = artwork;
    _paletteCache[songId] = scheme;

    return SongVisuals(artwork: artwork, scheme: scheme);
  }

  Uint8List? peekArtwork(int songId) {
    if (!_artworkCache.containsKey(songId)) return null;

    final artwork = _artworkCache.remove(songId);
    _artworkCache[songId] = artwork;
    return artwork;
  }

  Future<Uint8List?> loadArtwork(int songId, {bool priority = true}) {
    if (_artworkCache.containsKey(songId)) {
      return Future<Uint8List?>.value(peekArtwork(songId));
    }

    final existing = _artworkInFlight[songId];

    if (existing != null) {
      if (priority) {
        final index = _pendingArtwork.indexWhere((job) => job.songId == songId);

        if (index > 0) {
          final job = _pendingArtwork.removeAt(index);
          _pendingArtwork.insert(0, job);
        }
      }

      return existing;
    }

    final job = _ArtworkJob(songId);
    _artworkInFlight[songId] = job.completer.future;

    if (priority) {
      _pendingArtwork.insert(0, job);
    } else {
      _pendingArtwork.add(job);
    }

    _pumpArtwork();
    return job.completer.future;
  }

  Future<SongVisuals> load(int songId, {bool priority = true}) {
    final cached = peek(songId);

    if (cached != null) {
      return Future<SongVisuals>.value(cached);
    }

    final existing = _paletteInFlight[songId];

    if (existing != null) {
      if (priority) {
        _prioritizePalette(songId);
      }
      return existing.then(
        (scheme) => SongVisuals(artwork: peekArtwork(songId), scheme: scheme),
      );
    }

    return _loadVisuals(songId, priority: priority);
  }

  void preload(int songId) {
    unawaited(load(songId, priority: false));
  }

  Uri? peekSystemArtworkUri(int songId) {
    final file = _systemArtworkFiles.remove(songId);
    if (file == null) return null;
    _systemArtworkFiles[songId] = file;
    return file.uri;
  }

  Future<Uri?> preloadSystemArtworkUri(int songId) =>
      loadSystemArtworkUri(songId, priority: false);

  Future<Uri?> loadSystemArtworkUri(int songId, {bool priority = true}) {
    final cached = peekSystemArtworkUri(songId);
    if (cached != null) return Future<Uri?>.value(cached);
    final existing = _systemArtworkInFlight[songId];
    if (existing != null) {
      if (priority) loadArtwork(songId);
      return existing;
    }
    final request = _createSystemArtworkUri(songId, priority: priority);
    _systemArtworkInFlight[songId] = request;
    request.whenComplete(() => _systemArtworkInFlight.remove(songId));
    return request;
  }

  Future<Uri?> _createSystemArtworkUri(
    int songId, {
    required bool priority,
  }) async {
    final artwork = await loadArtwork(songId, priority: priority);
    if (artwork == null) return null;
    try {
      final directory = Directory(
        '${Directory.systemTemp.path}/media_player_system_artwork',
      );
      await directory.create(recursive: true);
      final file = File('${directory.path}/$songId.img');
      if (!await file.exists() || await file.length() != artwork.length) {
        await file.writeAsBytes(artwork, flush: true);
      }
      _systemArtworkFiles.remove(songId);
      _systemArtworkFiles[songId] = file;
      while (_systemArtworkFiles.length > _systemArtworkFileLimit) {
        final oldest = _systemArtworkFiles.keys.first;
        final removed = _systemArtworkFiles.remove(oldest);
        if (removed != null) {
          unawaited(removed.delete().then<void>((_) {}, onError: (_) {}));
        }
      }
      return file.uri;
    } catch (error) {
      debugPrint('System artwork caching failed for $songId: $error');
      return null;
    }
  }

  Future<SongVisuals> _loadVisuals(int songId, {required bool priority}) async {
    final artwork = await loadArtwork(songId, priority: priority);
    final cachedScheme = _paletteCache.remove(songId);

    if (cachedScheme != null) {
      _paletteCache[songId] = cachedScheme;
      return SongVisuals(artwork: artwork, scheme: cachedScheme);
    }

    if (artwork == null) {
      _storePalette(songId, fallbackScheme);
      return SongVisuals(artwork: null, scheme: fallbackScheme);
    }

    final scheme = await _loadPalette(songId, artwork, priority: priority);
    return SongVisuals(artwork: artwork, scheme: scheme);
  }

  Future<ColorScheme> _loadPalette(
    int songId,
    Uint8List artwork, {
    required bool priority,
  }) {
    final cached = _paletteCache.remove(songId);

    if (cached != null) {
      _paletteCache[songId] = cached;
      return Future<ColorScheme>.value(cached);
    }

    final existing = _paletteInFlight[songId];
    if (existing != null) {
      if (priority) {
        _prioritizePalette(songId);
      }
      return existing;
    }

    final job = _PaletteJob(songId, artwork);
    _paletteInFlight[songId] = job.completer.future;

    if (priority) {
      _pendingPalettes.insert(0, job);
    } else {
      _pendingPalettes.add(job);
    }

    _pumpPalettes();
    return job.completer.future;
  }

  void _prioritizePalette(int songId) {
    final index = _pendingPalettes.indexWhere((job) => job.songId == songId);

    if (index > 0) {
      final job = _pendingPalettes.removeAt(index);
      _pendingPalettes.insert(0, job);
    }
  }

  void _pumpArtwork() {
    while (_activeArtwork < _artworkConcurrentLimit &&
        _pendingArtwork.isNotEmpty) {
      final job = _pendingArtwork.removeAt(0);
      _activeArtwork++;
      unawaited(_runArtwork(job));
    }
  }

  Future<void> _runArtwork(_ArtworkJob job) async {
    Uint8List? artwork;

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
    } catch (error) {
      debugPrint('Artwork loading failed for ${job.songId}: $error');
    }

    _artworkCache[job.songId] = artwork;

    while (_artworkCache.length > _artworkCacheLimit) {
      _artworkCache.remove(_artworkCache.keys.first);
    }

    _artworkInFlight.remove(job.songId);
    _activeArtwork--;
    job.completer.complete(artwork);
    _pumpArtwork();
  }

  void _pumpPalettes() {
    while (_activePalettes < _paletteConcurrentLimit &&
        _pendingPalettes.isNotEmpty) {
      final job = _pendingPalettes.removeAt(0);
      _activePalettes++;
      unawaited(_runPalette(job));
    }
  }

  Future<void> _runPalette(_PaletteJob job) async {
    var scheme = fallbackScheme;

    try {
      scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(MemoryImage(job.artwork), width: 96, height: 96),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );
    } catch (error) {
      debugPrint('Palette loading failed for ${job.songId}: $error');
    }

    _storePalette(job.songId, scheme);
    _paletteInFlight.remove(job.songId);
    _activePalettes--;
    job.completer.complete(scheme);
    _pumpPalettes();
  }

  void _storePalette(int songId, ColorScheme scheme) {
    _paletteCache.remove(songId);
    _paletteCache[songId] = scheme;

    while (_paletteCache.length > _paletteCacheLimit) {
      _paletteCache.remove(_paletteCache.keys.first);
    }
  }
}

class _ArtworkJob {
  final int songId;
  final Completer<Uint8List?> completer = Completer<Uint8List?>();

  _ArtworkJob(this.songId);
}

class _PaletteJob {
  final int songId;
  final Uint8List artwork;
  final Completer<ColorScheme> completer = Completer<ColorScheme>();

  _PaletteJob(this.songId, this.artwork);
}
