import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/player_state.dart';
import '../services/song_filter.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.white24),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final query = _query.trim();

    final results = query.isEmpty
        ? <Song>[]
        : filterAndSortSongs(
            state.songs,
            query,
            SortOption.title,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: GestureDetector(
        onTap: () => _focusNode.unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Songs, artists…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                            _focusNode.requestFocus();
                          },
                        ),
                ),
                onChanged: (value) {
                  setState(() => _query = value);
                },
                onSubmitted: (_) => _focusNode.unfocus(),
              ),
            ),
            if (query.isNotEmpty && results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${results.length} '
                    '${results.length == 1 ? 'result' : 'results'}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: query.isEmpty
                  ? _emptyState(
                      icon: Icons.manage_search_rounded,
                      title: 'Find your next listen',
                      subtitle: 'Search the songs and artists on your device.',
                    )
                  : results.isEmpty
                      ? _emptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          subtitle: 'Try another song title or artist name.',
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          itemCount: results.length,
                          separatorBuilder: (_, index) {
                            return const SizedBox(height: 3);
                          },
                          itemBuilder: (context, index) {
                            final song = results[index];

                            return SongTile(
                              key: ValueKey(song.id),
                              song: song,
                              isCurrent: state.currentSong?.id == song.id,
                              isPlaying: state.playing,
                              onTap: () {
                                _focusNode.unfocus();
                                state.playFromLibrary(song, results);
                              },
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