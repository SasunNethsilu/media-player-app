import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/player_state.dart';
import 'providers/app_settings.dart';
import 'services/playback_session_store.dart';
import 'services/system_media_handler.dart';
import 'screens/library_screen.dart';
import 'screens/songs_screen.dart';
import 'widgets/mini_player.dart';
import 'providers/library_collections.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final systemMediaHandler = await AudioService.init<SystemMediaHandler>(
    builder: SystemMediaHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sasunnethsilu.musicplayer.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      artDownscaleWidth: 192,
      artDownscaleHeight: 192,
    ),
  );

  final preferences = SharedPreferencesAsync();
  final collections = LibraryCollections(preferences: preferences);
  final settings = AppSettings(preferences: preferences);
  final sessionStore = PlaybackSessionStore(preferences: preferences);
  await Future.wait([collections.load(), settings.load()]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryCollections>(create: (_) => collections),
        ChangeNotifierProvider<AppSettings>(create: (_) => settings),
        ChangeNotifierProvider<PlayerState>(
          create: (context) => PlayerState(
            collections: context.read<LibraryCollections>(),
            appSettings: context.read<AppSettings>(),
            sessionStore: sessionStore,
            systemMediaHandler: systemMediaHandler,
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101115);
    const surface = Color(0xFF1B1D24);

    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB8C7EE),
          brightness: Brightness.dark,
          surface: surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 84,
          titleSpacing: 20,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
          prefixIconColor: Colors.white54,
          suffixIconColor: Colors.white54,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.white24),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 70,
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFF292D38),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.white38,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (states) => IconThemeData(
              size: 23,
              color: states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.white38,
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF252832),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        dividerColor: Colors.white10,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final _songsKey = GlobalKey<SongsScreenState>();

  void _openAllSongs() {
    _songsKey.currentState?.clearSearch();
    setState(() => _selectedIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final showMiniPlayer = context.watch<PlayerState>().currentSong != null;
    final systemBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              LibraryScreen(onOpenAllSongs: _openAllSongs),
              SongsScreen(key: _songsKey),
            ],
          ),
          if (showMiniPlayer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 70 + systemBottom,
              child: const MiniPlayer(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_rounded),
            label: 'Songs',
          ),
        ],
      ),
    );
  }
}
