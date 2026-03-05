import 'package:flutter/material.dart';

class ExploreSearchBar extends StatelessWidget {
  const ExploreSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        color: Color(0xFF1A1A2E),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Search illustrations...',
        hintStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF9CA3AF),
          size: 20,
        ),
        filled: true,
        fillColor: const Color(0xFFEEF0FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
