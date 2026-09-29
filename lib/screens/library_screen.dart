import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';
import '../widgets/song_artwork.dart';
import '../widgets/search_sort_bar.dart';
import '../services/song_filter.dart';
import '../main.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with RouteAware {
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  SortOption _sortOption = SortOption.title;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _searchFocusNode.unfocus();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<PlayerState>().loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final displayedSongs = filterAndSortSongs(playerState.songs, _query, _sortOption);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Library')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            SearchSortBar(
              focusNode: _searchFocusNode,
              onQueryChanged: (value) => setState(() => _query = value),
              currentSort: _sortOption,
              onSortChanged: (option) => setState(() => _sortOption = option),
            ),
            Expanded(
              child: playerState.songs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : displayedSongs.isEmpty
                      ? const Center(child: Text('No matches'))
                      : ListView.builder(
                          itemCount: displayedSongs.length,
                          itemBuilder: (context, index) {
                            final song = displayedSongs[index];
                            return ListTile(
                              leading: SongArtwork(songId: song.id, size: 48, borderRadius: 4),
                              title: Text(song.title),
                              subtitle: Text(song.artist),
                              onTap: () => context.read<PlayerState>().playFromLibrary(song, displayedSongs),
                            );
                          },
                        ),
            ),
          ],
      ),
      )
    );
  }
}