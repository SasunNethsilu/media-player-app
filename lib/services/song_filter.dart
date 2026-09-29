import '../models/song.dart';

enum SortOption { title, artist }

List<Song> filterAndSortSongs(List<Song> songs, String query, SortOption sortOption) {
  var result = songs.where((song) {
    final q = query.toLowerCase();
    return song.title.toLowerCase().contains(q) ||
        song.artist.toLowerCase().contains(q);
  }).toList();

  result.sort((a, b) {
    return sortOption == SortOption.title
        ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
        : a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
  });

  return result;
}