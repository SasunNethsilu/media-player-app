import '../models/song.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';
import '../services/song_filter.dart';
import '../widgets/song_artwork.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final results = _query.isEmpty
        ? <Song>[]
        : filterAndSortSongs(playerState.songs, _query, SortOption.title);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: GestureDetector(
        onTap: () => _searchFocusNode.unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                focusNode: _searchFocusNode,
                decoration: const InputDecoration(
                  hintText: 'Search songs or artists',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? const Center(child: Text('Search your library'))
                  : results.isEmpty
                      ? const Center(child: Text('No matches'))
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final song = results[index];
                            return ListTile(
                              leading: SongArtwork(songId: song.id, size: 48, borderRadius: 4),
                              title: Text(song.title),
                              subtitle: Text(song.artist),
                              onTap: () => context.read<PlayerState>().playFromLibrary(song, results),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}