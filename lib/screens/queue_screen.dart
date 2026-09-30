import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_state.dart';
import '../widgets/song_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final currentSong = state.currentSong;
    final queue = state.queue;
    final queueKeys = state.queueKeys;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Queue'),
        actions: [
          IconButton(
            tooltip: 'Clear upcoming queue',
            onPressed: queue.isEmpty ? null : state.clearUpcomingQueue,
            icon: const Icon(Icons.clear_all_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentSong != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'PLAYING NOW',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SongTile(
                song: currentSong,
                isCurrent: true,
                isPlaying: state.playing,
              ),
            ),
            const SizedBox(height: 26),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Up next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${queue.length}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (queue.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Text(
                'Hold the handle to reorder · Swipe left to remove',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ),
          Expanded(
            child: queue.isEmpty
                ? const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            size: 52,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'You’re all caught up',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Choose a song from your library to start a queue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      state.reorderQueue(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: const Color(0xFF252832),
                        elevation: 8,
                        shadowColor: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      final entryKey = queueKeys[index];

                      return Dismissible(
                        key: ValueKey(entryKey),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => state.removeQueueEntry(entryKey),
                        background: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.only(right: 22),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: const Color(0xFF48262D),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFFFB4BD),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SongTile(
                            song: song,
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: Container(
                                width: 48,
                                height: 48,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.drag_handle_rounded,
                                  color: Colors.white54,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
