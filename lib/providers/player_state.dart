import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/library_scanner.dart';
import 'package:audio_service/audio_service.dart';

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Song> _songs = [];
  List<Song> _queue = [];
  final List<Song> _history = [];
  Song? _currentSong;

  PlayerState() {
    _player.playerStateStream.listen((_) => notifyListeners());

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playNext();
      }
    });
  }
  

  List<Song> get songs => _songs;
  List<Song> get queue => _queue;
  Song? get currentSong => _currentSong;
  AudioPlayer get player => _player;
  bool get isPlaying => _player.playing;

  Future<void> loadLibrary() async {
    _songs = await LibraryScanner().scanSongs();
    notifyListeners();
  }

  Future<void> play(Song song) async {
    _currentSong = song;
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.file(song.path),
        tag: MediaItem(
          id: song.id.toString(),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: Duration(milliseconds: song.durationMs),
        ),
      ),
    );
    _player.play();
    notifyListeners();
  }

  Future<void> playFromLibrary(Song song, List<Song> fromList) async {
    final startIndex = _songs.indexOf(song);
    _queue = _songs.sublist(startIndex + 1);
    await play(song);
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_currentSong != null) _history.add(_currentSong!);
    final next = _queue.removeAt(0);
    await play(next);
  }

  Future<void> playPrevious() async {
    if (_player.position > const Duration(seconds: 3) || _history.isEmpty) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_currentSong != null) _queue.insert(0, _currentSong!);
    final prev = _history.removeLast();
    await play(prev);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);
    notifyListeners();
  }

  void removeFromQueue(Song song) {
    _queue.remove(song);
    notifyListeners();
  }

  void togglePlayPause() {
    playing ? _player.pause() : _player.play();
  }

  bool get playing => _player.playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}