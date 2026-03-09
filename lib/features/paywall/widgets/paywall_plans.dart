import 'package:flutter/material.dart';

class PaywallPlans extends StatefulWidget {
  const PaywallPlans({super.key});

  @override
  State<PaywallPlans> createState() => _PaywallPlansState();
}

class _PaywallPlansState extends State<PaywallPlans> {

  String selectedPlan = "annual";

  Widget planCard(String id,String title,String price,String subtitle) {

    bool selected = selectedPlan == id;

    return GestureDetector(
      onTap: (){
        setState(() {
          selectedPlan = id;
        });
      },

      child: Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xff6C63FF) : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              color: Colors.black.withOpacity(.05),
            )
          ],
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                )
              ],
            ),

            Text(
              price,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        planCard("annual","Annual Plan","\$24.99","Save 48%"),
        planCard("monthly","Monthly Plan","\$3.99","Cancel anytime"),
        planCard("lifetime","Lifetime","\$49.99","Pay once"),

      ],
    );
  }
}