import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StickerGifPicker extends StatefulWidget {
  final Function(String stickerUrl) onSelectSticker;
  final Function(String gifUrl) onSelectGif;
  final VoidCallback onClose;

  const StickerGifPicker({
    super.key,
    required this.onSelectSticker,
    required this.onSelectGif,
    required this.onClose,
  });

  @override
  State<StickerGifPicker> createState() => _StickerGifPickerState();
}

class _StickerGifPickerState extends State<StickerGifPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _gifSearchQuery = '';

  // Coffee cup and expressive sticker sets (as shown in WhatsApp video frame_0026s.jpg)
  final List<String> _coffeeStickers = [
    'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1511920170033-f8396924c348?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1517256064527-09c73fc73e38?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1447933601403-0c6688de566e?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1507133750040-4a8f57021571?w=180&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1498804103079-a6351b050096?w=180&auto=format&fit=crop&q=80',
  ];

  final List<String> _cuteReactionStickers = [
    'https://api.dicebear.com/7.x/bottts/png?seed=HappyDolsy&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=CoolBot&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=HeartLove&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=LaughingJoy&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=ShockedWow&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=WavingHello&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=SleepyNight&size=150',
    'https://api.dicebear.com/7.x/bottts/png?seed=PartyTime&size=150',
    'https://api.dicebear.com/7.x/fun-emoji/png?seed=JoySparkle&size=150',
    'https://api.dicebear.com/7.x/fun-emoji/png?seed=FireEnergy&size=150',
    'https://api.dicebear.com/7.x/fun-emoji/png?seed=LoveHeartEyes&size=150',
    'https://api.dicebear.com/7.x/fun-emoji/png?seed=CoolShades&size=150',
  ];

  // High quality curated trending GIFs
  final List<Map<String, String>> _trendingGifs = [
    {
      'title': 'Thumbs Up',
      'url': 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif',
      'category': 'reactions',
    },
    {
      'title': 'Clapping',
      'url': 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif',
      'category': 'applause',
    },
    {
      'title': 'Laughing',
      'url': 'https://media.giphy.com/media/26n6Gx9moCgs1pUCA/giphy.gif',
      'category': 'happy',
    },
    {
      'title': 'Dancing Cat',
      'url': 'https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif',
      'category': 'dance',
    },
    {
      'title': 'Mind Blown',
      'url': 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif',
      'category': 'reactions',
    },
    {
      'title': 'Celebration Confetti',
      'url': 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif',
      'category': 'celebrate',
    },
    {
      'title': 'Heart Love',
      'url': 'https://media.giphy.com/media/26BRv0ThflsHCqDrG/giphy.gif',
      'category': 'love',
    },
    {
      'title': 'Yes Definitely',
      'url': 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/giphy.gif',
      'category': 'reactions',
    },
    {
      'title': 'Facepalm',
      'url': 'https://media.giphy.com/media/6yRVg0HWzgS88/giphy.gif',
      'category': 'reactions',
    },
    {
      'title': 'Popcorn Waiting',
      'url': 'https://media.giphy.com/media/GLbiGvv9Ri3EQ/giphy.gif',
      'category': 'fun',
    },
  ];

  int _selectedStickerPack = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 310,
      decoration: const BoxDecoration(
        color: Color(0xFF1F2C34),
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Column(
        children: [
          // Top search & tabs header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF182229),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3942),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _tabController.index == 0 ? 'Search stickers...' : 'Search Tenor / GIFs...',
                        hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _gifSearchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        setState(() => _gifSearchQuery = val.trim().toLowerCase());
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A3942),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicator: BoxDecoration(
                      color: const Color(0xFF00A884),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sticky_note_2_outlined, size: 16),
                            SizedBox(width: 4),
                            Text('Stickers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gif_box_outlined, size: 16),
                            SizedBox(width: 4),
                            Text('GIFs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                    onTap: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Content body
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Stickers View
                _buildStickersTab(),

                // 2. GIFs View
                _buildGifsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickersTab() {
    final activeList = _selectedStickerPack == 0
        ? _coffeeStickers
        : (_selectedStickerPack == 1 ? _cuteReactionStickers : [..._coffeeStickers, ..._cuteReactionStickers]);

    final filtered = _searchController.text.isEmpty
        ? activeList
        : activeList.where((u) => u.toLowerCase().contains(_searchController.text.toLowerCase())).toList();

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final stickerUrl = filtered[index];
              return GestureDetector(
                onTap: () => widget.onSelectSticker(stickerUrl),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A3942).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: CachedNetworkImage(
                    imageUrl: stickerUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884))),
                    ),
                    errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                  ),
                ),
              );
            },
          ),
        ),

        // Sticker packs bottom tab selector (frame_0026s.jpg)
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: const Color(0xFF182229),
          child: Row(
            children: [
              _buildStickerPackTab(0, Icons.local_cafe_rounded, 'Coffee'),
              _buildStickerPackTab(1, Icons.face_retouching_natural, 'Avatars'),
              _buildStickerPackTab(2, Icons.stars_rounded, 'All'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStickerPackTab(int index, IconData icon, String label) {
    final isSelected = _selectedStickerPack == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedStickerPack = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00A884).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: const Color(0xFF00A884), width: 1.2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF00A884) : Colors.white60),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGifsTab() {
    final filteredGifs = _gifSearchQuery.isEmpty
        ? _trendingGifs
        : _trendingGifs.where((g) {
            final title = (g['title'] ?? '').toLowerCase();
            final cat = (g['category'] ?? '').toLowerCase();
            return title.contains(_gifSearchQuery) || cat.contains(_gifSearchQuery);
          }).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemCount: filteredGifs.length,
      itemBuilder: (context, index) {
        final gif = filteredGifs[index];
        final url = gif['url']!;
        return GestureDetector(
          onTap: () => widget.onSelectGif(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: const Color(0xFF2A3942),
                    child: const Center(
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884))),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF2A3942),
                    child: const Icon(Icons.gif, color: Colors.white54, size: 36),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      gif['title'] ?? 'GIF',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
