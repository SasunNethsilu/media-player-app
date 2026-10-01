import 'song.dart';

const shortAudioThresholdMs = 30000;

enum AlbumSortOption { title, artist, newest }

enum ArtistSortOption { name, albumCount, songCount }

class AlbumCollection {
  final String key;
  final String title;
  final String artist;
  final int? year;
  final List<Song> songs;

  AlbumCollection({
    required this.key,
    required this.title,
    required this.artist,
    required this.year,
    required Iterable<Song> songs,
  }) : songs = List.unmodifiable(songs);

  Song get artworkSong => songs.first;
}

class ArtistCollection {
  final String key;
  final String name;
  final List<Song> songs;
  final List<AlbumCollection> albums;

  ArtistCollection({
    required this.key,
    required this.name,
    required Iterable<Song> songs,
  }) : songs = List.unmodifiable(songs),
       albums = List.unmodifiable(groupAlbums(songs));

  Song get artworkSong => songs.first;
}

bool isUnknownMetadata(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == '<unknown>' ||
      normalized == 'unknown album' ||
      normalized == 'unknown artist';
}

List<Song> applyShortAudioFilter(
  Iterable<Song> songs, {
  required bool enabled,
}) {
  if (!enabled) return List<Song>.of(songs);
  return songs
      .where(
        (song) =>
            song.durationMs <= 0 || song.durationMs >= shortAudioThresholdMs,
      )
      .toList();
}

List<AlbumCollection> groupAlbums(
  Iterable<Song> songs, {
  AlbumSortOption sort = AlbumSortOption.title,
}) {
  final grouped = <String, List<Song>>{};

  for (final song in songs) {
    grouped.putIfAbsent(_albumKey(song), () => []).add(song);
  }

  final albums = grouped.entries.map((entry) {
    final tracks = orderAlbumSongs(entry.value);
    final albumArtists = tracks
        .map((song) => _known(song.albumArtist))
        .whereType<String>()
        .toSet();
    final artists =
        (albumArtists.isNotEmpty
                ? albumArtists
                : tracks.map((song) => _known(song.artist)).whereType<String>())
            .toSet();
    final years = tracks
        .map((song) => song.year)
        .whereType<int>()
        .where((year) => year > 0)
        .toSet();

    return AlbumCollection(
      key: entry.key,
      title: _known(tracks.first.album) ?? 'Unknown Album',
      artist: artists.isEmpty
          ? 'Unknown Artist'
          : artists.length == 1
          ? artists.first
          : 'Various Artists',
      year: years.length == 1 ? years.first : null,
      songs: tracks,
    );
  }).toList();

  albums.sort((a, b) {
    switch (sort) {
      case AlbumSortOption.title:
        return _compareText(a.title, b.title, a.key, b.key);
      case AlbumSortOption.artist:
        return _compareText(a.artist, b.artist, a.title, b.title);
      case AlbumSortOption.newest:
        final year = (b.year ?? -1).compareTo(a.year ?? -1);
        return year != 0 ? year : _compareText(a.title, b.title, a.key, b.key);
    }
  });

  return albums;
}

List<ArtistCollection> groupArtists(
  Iterable<Song> songs, {
  ArtistSortOption sort = ArtistSortOption.name,
}) {
  final grouped = <String, List<Song>>{};

  for (final song in songs) {
    final key = song.artistId != null && song.artistId! > 0
        ? 'id:${song.artistId}'
        : _known(song.artist) == null
        ? 'unknown'
        : 'name:${song.artist.trim().toLowerCase()}';
    grouped.putIfAbsent(key, () => []).add(song);
  }

  final artists = grouped.entries.map((entry) {
    final artistSongs = entry.value.toList()
      ..sort((a, b) => _compareText(a.title, b.title, '${a.id}', '${b.id}'));
    return ArtistCollection(
      key: entry.key,
      name: _known(artistSongs.first.artist) ?? 'Unknown Artist',
      songs: artistSongs,
    );
  }).toList();

  artists.sort((a, b) {
    switch (sort) {
      case ArtistSortOption.name:
        return _compareText(a.name, b.name, a.key, b.key);
      case ArtistSortOption.albumCount:
        final count = b.albums.length.compareTo(a.albums.length);
        return count != 0 ? count : _compareText(a.name, b.name, a.key, b.key);
      case ArtistSortOption.songCount:
        final count = b.songs.length.compareTo(a.songs.length);
        return count != 0 ? count : _compareText(a.name, b.name, a.key, b.key);
    }
  });

  return artists;
}

List<Song> orderAlbumSongs(Iterable<Song> songs) {
  final ordered = List<Song>.of(songs);
  final positions = <String>{};
  final reliable =
      ordered.length > 1 &&
      ordered.every((song) {
        final track = song.trackNumber;
        if (track == null || track <= 0) return false;
        return positions.add('${song.discNumber ?? 1}:$track');
      });

  ordered.sort((a, b) {
    if (reliable) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      if (disc != 0) return disc;
      final track = a.trackNumber!.compareTo(b.trackNumber!);
      if (track != 0) return track;
    }

    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (title != 0) return title;
    final artist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    return artist != 0 ? artist : a.id.compareTo(b.id);
  });

  return ordered;
}

String _albumKey(Song song) {
  if (song.albumId != null && song.albumId! > 0) {
    return 'id:${song.albumId}';
  }

  final album = _known(song.album)?.toLowerCase();
  final albumArtist = _known(song.albumArtist)?.toLowerCase();
  final folder = _folder(song.path).toLowerCase();

  if (album == null) return 'unknown-song:${song.id}';
  if (albumArtist != null) {
    return 'meta:$album|album-artist:$albumArtist|year:${song.year ?? 'unknown'}';
  }
  if (folder.isNotEmpty) return 'meta:$album|folder:$folder';

  final artist = _known(song.artist)?.toLowerCase();
  return 'meta:$album|artist:${artist ?? 'unknown'}';
}

String? _known(String? value) {
  if (value == null || isUnknownMetadata(value)) return null;
  return value.trim();
}

String _folder(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator <= 0 ? '' : normalized.substring(0, separator);
}

int _compareText(String a, String b, String fallbackA, String fallbackB) {
  final result = a.toLowerCase().compareTo(b.toLowerCase());
  return result != 0
      ? result
      : fallbackA.toLowerCase().compareTo(fallbackB.toLowerCase());
}
