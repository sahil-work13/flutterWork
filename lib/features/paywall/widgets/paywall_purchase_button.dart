import 'package:flutter/material.dart';

class PaywallPurchaseButton extends StatelessWidget {
  const PaywallPurchaseButton({super.key});

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.all(20),

      child: Column(
        children: [

          ElevatedButton(
            onPressed: (){

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Processing Purchase..."),
                ),
              );

            },

            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xffFF6B9D),
              minimumSize: const Size(double.infinity,55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),

            child: const Text(
              "Start 3-Day Free Trial ✨",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            "No charge during trial • Cancel anytime",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          )

        ],
      ),
    );
  }
}