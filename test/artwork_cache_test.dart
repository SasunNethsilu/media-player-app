import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/services/artwork_palette_service.dart';
import 'package:media_player/widgets/song_artwork.dart';

void main() {
  testWidgets('song thumbnails reuse artwork without deriving a palette', (
    tester,
  ) async {
    const songId = 910001;
    const channel = MethodChannel('com.lucasjosino.on_audio_query');
    var artworkQueries = 0;
    final bytes = await tester.runAsync(() async {
      final image = await createTestImage(width: 8, height: 8, cache: false);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'queryArtwork') return null;
      artworkQueries++;
      return bytes;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SongArtwork(songId: songId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('art-$songId')), findsOneWidget);
    expect(artworkQueries, 1);
    expect(ArtworkPaletteService.shared.peek(songId), isNull);

    await tester.runAsync(() async {
      await ArtworkPaletteService.shared.load(songId);
    });

    expect(artworkQueries, 1);
    expect(ArtworkPaletteService.shared.peek(songId), isNotNull);

    final service = ArtworkPaletteService.shared;
    final prepared = await tester.runAsync(
      () => service.preloadSystemArtworkUri(songId),
    );
    expect(prepared, isNotNull);
    final written = await tester.runAsync(
      () => File.fromUri(prepared!).readAsBytes(),
    );
    expect(written, bytes);
    expect(service.peekSystemArtworkUri(songId), prepared);
    expect(await service.loadSystemArtworkUri(songId), prepared);
    expect(artworkQueries, 1);
  });
}
