import 'package:flutter/material.dart';

class PaywallFeatures extends StatelessWidget {
  const PaywallFeatures({super.key});

  @override
  Widget build(BuildContext context) {

    final features = [
      ["🖼️","200+ Illustrations","Including all future releases"],
      ["🚫","No Ads","Pure distraction-free coloring"],
      ["📹","Speed Replay","Share your coloring journey"],
      ["📸","4K Export","High resolution artwork"],
      ["🎨","Unlimited Palettes","Save as many as you want"],
      ["🌈","Color Harmony AI","Smart color suggestions"],
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black.withOpacity(.06),
          )
        ],
      ),
      child: Column(
        children: features.map((f){

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [

                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xffEEEFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(f[0])),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        f[1],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Text(
                        f[2],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),

                    ],
                  ),
                ),

                const Icon(Icons.check_circle,color: Colors.green)

              ],
            ),
          );

        }).toList(),
      ),
    );
  }
}