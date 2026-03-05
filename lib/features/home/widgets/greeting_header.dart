import 'package:flutter/material.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.greetingText,
    required this.streakDays,
    required this.notifications,
    required this.onStreakTap,
    required this.onNotificationTap,
  });

  final String greetingText;
  final int streakDays;
  final int notifications;
  final VoidCallback onStreakTap;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greetingText,
                  style: const TextStyle(
                    color: Color(0xFF7C7C9A),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Let's create!",
                  style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: <Widget>[
              Material(
                color: const Color(0xFFFFF7E5),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onStreakTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('🔥', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 4),
                        Text(
                          '$streakDays',
                          style: const TextStyle(
                            color: Color(0xFFE65100),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  shadowColor: const Color.fromRGBO(0, 0, 0, 0.08),
                  elevation: 2,
                  child: InkWell(
                    onTap: onNotificationTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      children: <Widget>[
                        const Center(
                          child: Icon(
                            Icons.notifications_none_rounded,
                            size: 20,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        if (notifications > 0)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF6B9D),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$notifications',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
