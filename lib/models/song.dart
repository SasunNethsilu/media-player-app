class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final int durationMs;
  final String? albumArtPath;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.durationMs,
    this.albumArtPath
  });
}