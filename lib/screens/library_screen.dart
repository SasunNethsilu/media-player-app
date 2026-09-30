import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_state.dart';
import '../services/song_filter.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  SortOption _sortOption = SortOption.title;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (mounted) {
        context.read<PlayerState>().loadLibrary();
      }
    });
  }

  Widget _message({
    required IconData icon,
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final songs = filterAndSortSongs(state.songs, '', _sortOption);

    Widget content;

    if (state.isLoadingLibrary) {
      content = const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (state.libraryError != null) {
      content = _message(
        icon: Icons.info_outline_rounded,
        text: state.libraryError!,
        buttonLabel: 'Try again',
        onPressed: () => state.loadLibrary(),
      );
    } else if (songs.isEmpty) {
      content = _message(
        icon: Icons.library_music_outlined,
        text: 'Your music belongs here.\nAdd songs to your device to get started.',
        buttonLabel: 'Scan for music',
        onPressed: () => state.loadLibrary(),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: state.loadLibrary,
        child: ListView.separated(
          key: const PageStorageKey('library-songs'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          itemCount: songs.length,
          separatorBuilder: (_, index) => const SizedBox(height: 3),
          itemBuilder: (context, index) {
            final song = songs[index];

            return SongTile(
              key: ValueKey(song.id),
              song: song,
              isCurrent: state.currentSong?.id == song.id,
              isPlaying: state.playing,
              onTap: () => state.playFromLibrary(song, songs),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Library'),
            SizedBox(height: 5),
            Text(
              'All your music, in one place.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF292D38),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Songs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${songs.length} tracks',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<SortOption>(
                  tooltip: 'Sort songs',
                  initialValue: _sortOption,
                  onSelected: (option) {
                    setState(() => _sortOption = option);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: SortOption.title,
                      child: Text('Song title'),
                    ),
                    PopupMenuItem(
                      value: SortOption.artist,
                      child: Text('Artist name'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _sortOption == SortOption.title
                              ? 'Title'
                              : 'Artist',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.sort_rounded,
                          color: Colors.white60,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}