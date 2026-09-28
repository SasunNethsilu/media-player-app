import 'package:flutter/material.dart';
import 'package:media_player/widgets/mini_player.dart';
import 'package:provider/provider.dart';
import 'providers/player_state.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => PlayerState(),
      child: const MyApp(),
      )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const LibraryScreen(),
        bottomNavigationBar: const MiniPlayer(),
      ),
    );
  }
}



