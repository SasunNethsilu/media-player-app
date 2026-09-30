import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class FakeAudioPlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final processing = StreamController<ProcessingState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final loadedIds = <int>[];
  final audibleIds = <int>[];
  final seeks = <Duration?>[];
  final playRequests = <Completer<void>>[];
  final failures = <int, Object>{};
  final loadGates = <int, Completer<void>>{};
  Completer<void>? seekGate;
  Completer<void>? loading;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int? sourceId;
  MediaItem? mediaItem;
  bool disposed = false;

  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  Stream<Duration?> get durationStream => Stream.value(duration);
  @override
  Stream<Duration> get positionStream => Stream.value(position);
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  void emit(ProcessingState state) {
    if (disposed) return;
    processingState = state;
    processing.add(state);
    states.add(PlayerState(playing, state));
  }

  void complete() {
    position = duration!;
    emit(ProcessingState.completed);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    final tag = (source as UriAudioSource).tag as MediaItem;
    final id = int.parse(tag.id);
    loadedIds.add(id);
    emit(ProcessingState.loading);
    if (loading != null) await loading!.future;
    if (loadGates[id] != null) await loadGates[id]!.future;
    if (disposed) return null;
    if (failures[id] case final failure?) {
      emit(ProcessingState.idle);
      throw failure;
    }
    sourceId = id;
    mediaItem = tag;
    position = initialPosition ?? Duration.zero;
    emit(ProcessingState.ready);
    return duration;
  }

  @override
  Future<void> play() {
    playCalls++;
    playing = true;
    audibleIds.add(sourceId!);
    states.add(PlayerState(playing, processingState));
    final request = Completer<void>();
    playRequests.add(request);
    return request.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
    states.add(PlayerState(playing, processingState));
  }

  @override
  Future<void> seek(Duration? value, {int? index}) async {
    seeks.add(value);
    if (seekGate != null) await seekGate!.future;
    if (disposed) return;
    position = value ?? Duration.zero;
    emit(ProcessingState.ready);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    playing = false;
    for (final request in playRequests) {
      if (!request.isCompleted) request.complete();
    }
    await states.close();
    await processing.close();
    await events.close();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
    emit(ProcessingState.idle);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
