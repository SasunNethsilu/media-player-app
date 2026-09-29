import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<PlayerState>().loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();

    return Scaffold(
      appBar: AppBar(title: Text('Your Library')),
      body: playerState.songs.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : ListView.builder(
          itemCount: playerState.songs.length,
          itemBuilder: (context, index) {
            final song = playerState.songs[index];
            return ListTile(
              title: Text(song.title),
              subtitle: Text(song.artist),
              onTap:() => context.read<PlayerState>().playFromLibrary(song),
            );
          },
      ),
    );
  }
}