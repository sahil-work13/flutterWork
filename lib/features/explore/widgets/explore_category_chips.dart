import 'package:flutter/material.dart';

class ExploreCategoryChips extends StatelessWidget {
  const ExploreCategoryChips({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, int index) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String category = categories[index];
          final bool active = category == selectedCategory;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(category),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF6C63FF) : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF6C63FF)
                        : const Color(0xFFEBEBF5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF7C7C9A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
