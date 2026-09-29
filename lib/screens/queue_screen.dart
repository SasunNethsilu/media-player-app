import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Up Next')),
      body: playerState.queue.isEmpty
          ? const Center(child: Text('Queue is empty'))
          : ReorderableListView.builder(
              itemCount: playerState.queue.length,
              onReorderItem: (oldIndex, newIndex) {
                context.read<PlayerState>().reorderQueue(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final song = playerState.queue[index];
                return Dismissible(
                  key: ValueKey(song.id), // required, unique per item
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => context.read<PlayerState>().removeFromQueue(song),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: ListTile(
                    title: Text(song.title),
                    subtitle: Text(song.artist),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                );
              },
            ),
    );
  }
}