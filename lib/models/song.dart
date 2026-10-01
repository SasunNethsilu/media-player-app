class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final int durationMs;
  final String? albumArtPath;
  final int? albumId;
  final int? artistId;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.durationMs,
    this.albumArtPath,
    this.albumId,
    this.artistId,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
  });
}
