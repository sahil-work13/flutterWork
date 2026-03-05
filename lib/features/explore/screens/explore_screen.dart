import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/models/explore_item.dart';
import 'package:flutterwork/features/explore/services/explore_catalog_service.dart';
import 'package:flutterwork/features/explore/widgets/explore_category_chips.dart';
import 'package:flutterwork/features/explore/widgets/explore_image_card.dart';
import 'package:flutterwork/features/explore/widgets/explore_search_bar.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import 'package:flutterwork/features/paint/basic_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<ExploreItem> _items = <ExploreItem>[];
  late String _selectedCategory;
  String _searchQuery = '';
  bool _loading = true;
  String? _errorMessage;
  final Set<String> _likedItemPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'All';
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final List<ExploreItem> loaded = await ExploreCatalogService.loadItems();
      if (!mounted) return;
      setState(() {
        _items = loaded;
        final Set<String> availableCategories = loaded
            .map((ExploreItem item) => item.category)
            .toSet();
        if (_selectedCategory != 'All' &&
            !availableCategories.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }
        _loading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Unable to load images from assets/images.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> categories = _buildCategories();
    final List<ExploreItem> visibleItems = _buildVisibleItems();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      body: Stack(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Explore 🔍',
                        style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExploreSearchBar(
                        controller: _searchController,
                        onChanged: (String value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      ExploreCategoryChips(
                        categories: categories,
                        selectedCategory: _selectedCategory,
                        onSelect: (String category) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBodyContent(visibleItems)),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNavBar(activeIndex: 1, onTap: _onBottomNavTap),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(List<ExploreItem> visibleItems) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(
            color: Color(0xFF7C7C9A),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (visibleItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 96),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('🔍', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text(
                'No results found',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Try a different search or category',
                style: TextStyle(
                  color: Color(0xFF7C7C9A),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 108),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.74,
      ),
      itemCount: visibleItems.length,
      itemBuilder: (BuildContext context, int index) {
        final ExploreItem item = visibleItems[index];
        return ExploreImageCard(
          item: item,
          isLiked: _likedItemPaths.contains(item.assetPath),
          onTap: () => _openCanvas(item.assetPath),
          onToggleLike: () {
            setState(() {
              if (!_likedItemPaths.add(item.assetPath)) {
                _likedItemPaths.remove(item.assetPath);
              }
            });
          },
        );
      },
    );
  }

  List<String> _buildCategories() {
    final List<String> dynamicCategories =
        _items.map((ExploreItem item) => item.category).toSet().toList()
          ..sort();
    return <String>['All', ...dynamicCategories];
  }

  List<ExploreItem> _buildVisibleItems() {
    final String normalizedSearch = _searchQuery.trim().toLowerCase();
    return _items.where((ExploreItem item) {
      final bool categoryMatches =
          _selectedCategory == 'All' || item.category == _selectedCategory;
      if (!categoryMatches) return false;
      if (normalizedSearch.isEmpty) return true;
      return item.title.toLowerCase().contains(normalizedSearch);
    }).toList();
  }

  void _openCanvas(String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BasicScreen(imagePath: imagePath),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    if (index == 1) return;
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This tab will be available soon.')),
    );
  }
}
