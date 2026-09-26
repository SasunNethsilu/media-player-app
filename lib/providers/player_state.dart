import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/library_scanner.dart';

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Song> _songs = [];
  Song? _currentSong;

  List<Song> get songs => _songs;
  Song? get currentSong => _currentSong;
  AudioPlayer get player => _player;

  Future<void> loadLibrary() async {
    _songs = await LibraryScanner().scanSongs();
    notifyListeners();
  }

  Future<void> play(Song song) async {
    _currentSong = song;
    await _player.setFilePath(song.path);
    _player.play();
    notifyListeners();
  }

  void pause() {
    _player.pause();
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}