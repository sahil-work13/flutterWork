import 'package:flutter/material.dart';
import 'package:flutterwork/features/paint/screens/basic_screen.dart';
import 'package:flutterwork/core/data/canvas_image_assets.dart';

class GalleryItem extends StatelessWidget {
  final Map<String, dynamic> data;

  const GalleryItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final int imageId = data["id"];
    final int progress = data["progress"] ?? 0;
    final String title = data["title"] ?? "Artwork ${imageId + 1}";

    return GestureDetector(
      onTap: () {
        final String originalPath = CanvasImageAssets.all[imageId];

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BasicScreen(
              imagePath: originalPath,
              imageIndex: imageId,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              blurRadius: 15,
              offset: const Offset(0, 5),
              color: const Color(0xFF6C63FF).withOpacity(.08),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Artwork Preview
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.asset(
                        CanvasImageAssets.all[imageId],
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                  ),

                  /// Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(20)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.02),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            /// Info Section
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Color(0xFF1A1A2E),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),

                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: progress >= 95
                              ? Colors.greenAccent
                              : const Color(0xFF6C63FF).withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 10, color: Color(0xFF6C63FF)),
                      const SizedBox(width: 4),
                      Text(
                        "$progress% Completed",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C63FF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}