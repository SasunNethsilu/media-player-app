import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/library_scanner.dart';

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Song> _songs = [];
  List<Song> _queue = [];
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
    await _player.setFilePath(song.path);
    _player.play();
  }

  Future<void> playFromLibrary(Song song) async {
    final startIndex = _songs.indexOf(song);
    _queue = _songs.sublist(startIndex + 1);
    await play(song);
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    final next = _queue.removeAt(0);
    await play(next);
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