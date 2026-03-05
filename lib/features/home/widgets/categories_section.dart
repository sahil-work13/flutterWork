import 'package:flutter/material.dart';

class CategoriesSection extends StatelessWidget {
  const CategoriesSection({
    super.key,
    required this.categories,
    this.onTapCategory,
    this.labelBuilder,
  });

  final List<String> categories;
  final ValueChanged<String>? onTapCategory;
  final String Function(String category)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Categories',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemBuilder: (BuildContext context, int index) {
              final String category = categories[index];
              final String label = labelBuilder?.call(category) ?? category;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTapCategory == null
                      ? null
                      : () => onTapCategory!(category),
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: const Color(0xFFE9E8F4),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF7C7C9A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, int index) => const SizedBox(width: 8),
            itemCount: categories.length,
          ),
        ),
      ],
    );
  }
}
