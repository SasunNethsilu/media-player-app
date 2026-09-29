import 'package:flutter/material.dart';
import '../services/song_filter.dart';

class SearchSortBar extends StatelessWidget {
  final ValueChanged<String> onQueryChanged;
  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;
  final FocusNode focusNode;

  const SearchSortBar({
    super.key,
    required this.onQueryChanged,
    required this.currentSort,
    required this.onSortChanged,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: focusNode,
              decoration: const InputDecoration(
                hintText: 'Search songs or artists',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: onQueryChanged,
            ),
          ),
          PopupMenuButton<SortOption>(
            icon: const Icon(Icons.sort),
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: SortOption.title, child: Text('Sort by Title')),
              PopupMenuItem(value: SortOption.artist, child: Text('Sort by Artist')),
            ],
          ),
        ],
      ),
    );
  }
}