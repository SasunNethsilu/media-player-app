import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/services/song_filter.dart';

void main() {
  late List<Song> songs;

  setUp(() {
    songs = [
      Song(
        id: 1,
        title: 'night Drive',
        artist: 'Alpha',
        album: 'Roads',
        path: '/music/night.mp3',
        durationMs: 180000,
      ),
      Song(
        id: 2,
        title: 'Aurora',
        artist: 'zebra',
        album: 'Night Sky',
        path: '/music/aurora.mp3',
        durationMs: 240000,
      ),
      Song(
        id: 3,
        title: 'blue Hour',
        artist: 'Midnight Band',
        album: 'Dawn',
        path: '/music/blue.mp3',
        durationMs: 210000,
      ),
    ];
  });

  test('search matches titles and artists regardless of case', () {
    final result = filterAndSortSongs(songs, 'NIGHT', SortOption.title);

    expect(result, orderedEquals([songs[2], songs[0]]));
  });

  test('empty search sorts all songs by title without changing the library', () {
    final original = List<Song>.of(songs);

    final result = filterAndSortSongs(songs, '', SortOption.title);

    expect(result, orderedEquals([original[1], original[2], original[0]]));
    expect(songs, orderedEquals(original));
  });

  test('artist sort orders songs regardless of case', () {
    final result = filterAndSortSongs(songs, '', SortOption.artist);

    expect(result, orderedEquals([songs[0], songs[2], songs[1]]));
  });

  test('unmatched search returns no songs', () {
    expect(filterAndSortSongs(songs, 'missing', SortOption.title), isEmpty);
  });

  test('empty library returns no songs', () {
    expect(filterAndSortSongs([], '', SortOption.title), isEmpty);
  });
}
