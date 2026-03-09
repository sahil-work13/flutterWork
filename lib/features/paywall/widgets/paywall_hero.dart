import 'package:flutter/material.dart';

class PaywallHero extends StatelessWidget {
  const PaywallHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xff6C63FF), Color(0xffA78BFA)],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                blurRadius: 40,
                color: const Color(0xff6C63FF).withOpacity(.4),
              )
            ],
          ),
          child: const Center(
            child: Text(
              "👑",
              style: TextStyle(fontSize: 42),
            ),
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          "ColorFill Pro",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          "Unlock the full creative experience",
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}