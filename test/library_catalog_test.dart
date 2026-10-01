import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/library_catalog.dart';
import 'package:media_player/models/song.dart';

Song song({
  required int id,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  String? albumArtist,
  int? albumId,
  int? artistId,
  int? track,
  int? disc,
  int? year,
  int durationMs = 180000,
  String? path,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    path: path ?? '/music/$album/$id.mp3',
    durationMs: durationMs,
    albumArtist: albumArtist,
    albumId: albumId,
    artistId: artistId,
    trackNumber: track,
    discNumber: disc,
    year: year,
  );
}

void main() {
  test('album IDs keep equal album names in separate collections', () {
    final albums = groupAlbums([
      song(id: 1, album: 'Greatest Hits', albumId: 10),
      song(id: 2, album: 'Greatest Hits', albumId: 20),
    ]);

    expect(albums, hasLength(2));
    expect(albums.map((album) => album.key), containsAll(['id:10', 'id:20']));
  });

  test('fallback album identity does not group equal names alone', () {
    final albums = groupAlbums([
      song(id: 1, album: 'Live', artist: 'One', path: '/music/one/live.mp3'),
      song(id: 2, album: 'Live', artist: 'Two', path: '/music/two/live.mp3'),
    ]);

    expect(albums, hasLength(2));
  });

  test('album artist groups a compilation when no album ID is available', () {
    final albums = groupAlbums([
      song(
        id: 1,
        artist: 'Singer One',
        albumArtist: 'Various Artists',
        path: '/disc1/one.mp3',
      ),
      song(
        id: 2,
        artist: 'Singer Two',
        albumArtist: 'Various Artists',
        path: '/disc2/two.mp3',
      ),
    ]);

    expect(albums, hasLength(1));
    expect(albums.single.artist, 'Various Artists');
  });

  test(
    'album tracks use disc and track order when every position is reliable',
    () {
      final songs = [
        song(id: 1, title: 'Third', track: 1, disc: 2),
        song(id: 2, title: 'Second', track: 2, disc: 1),
        song(id: 3, title: 'First', track: 1, disc: 1),
      ];

      expect(orderAlbumSongs(songs).map((item) => item.id), [3, 2, 1]);
    },
  );

  test(
    'album tracks use title fallback for incomplete or duplicate positions',
    () {
      final incomplete = [
        song(id: 1, title: 'Zulu', track: 1),
        song(id: 2, title: 'Alpha'),
      ];
      final duplicate = [
        song(id: 3, title: 'Zulu', track: 1),
        song(id: 4, title: 'Alpha', track: 1),
      ];

      expect(orderAlbumSongs(incomplete).map((item) => item.id), [2, 1]);
      expect(orderAlbumSongs(duplicate).map((item) => item.id), [4, 3]);
    },
  );

  test('artist IDs take precedence over matching display names', () {
    final artists = groupArtists([
      song(id: 1, artist: 'The Band', artistId: 40),
      song(id: 2, artist: 'The Band', artistId: 50),
    ]);

    expect(artists, hasLength(2));
  });

  test('missing metadata receives clear collection labels', () {
    final unknown = song(
      id: 1,
      artist: 'Unknown Artist',
      album: 'Unknown Album',
      path: '/music/missing/song.mp3',
    );

    expect(groupAlbums([unknown]).single.title, 'Unknown Album');
    expect(groupAlbums([unknown]).single.artist, 'Unknown Artist');
    expect(groupArtists([unknown]).single.name, 'Unknown Artist');
  });

  test('tracks without album metadata remain distinct collections', () {
    final albums = groupAlbums([
      song(id: 1, album: 'Unknown Album', path: '/music/missing/one.mp3'),
      song(id: 2, album: 'Unknown Album', path: '/music/missing/two.mp3'),
    ]);

    expect(albums, hasLength(2));
    expect(albums.every((album) => album.title == 'Unknown Album'), isTrue);
  });

  test('short-audio filter is disabled by default and retains source data', () {
    final songs = [
      song(id: 1, durationMs: 1000),
      song(id: 2, durationMs: 30000),
      song(id: 3, durationMs: 0),
    ];

    final disabled = applyShortAudioFilter(songs, enabled: false);
    final enabled = applyShortAudioFilter(songs, enabled: true);

    expect(disabled.map((item) => item.id), [1, 2, 3]);
    expect(enabled.map((item) => item.id), [2, 3]);
    expect(songs.map((item) => item.id), [1, 2, 3]);
  });

  test('album and artist collection sorting is deterministic', () {
    final songs = [
      song(id: 1, album: 'Old', artist: 'Zulu', year: 1999),
      song(id: 2, album: 'New', artist: 'Alpha', year: 2025),
      song(id: 3, album: 'New', artist: 'Alpha', year: 2025),
    ];

    expect(groupAlbums(songs, sort: AlbumSortOption.newest).first.title, 'New');
    expect(
      groupArtists(songs, sort: ArtistSortOption.songCount).first.name,
      'Alpha',
    );
  });
}
