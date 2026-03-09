import 'package:flutter/material.dart';
import '../widgets/paywall_header.dart';
import '../widgets/paywall_hero.dart';
import '../widgets/paywall_features.dart';
import '../widgets/paywall_plans.dart';
import '../widgets/paywall_purchase_button.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F5F7),

      body: SafeArea(
        child: Column(
          children: [

            const PaywallHeader(),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: const [

                    SizedBox(height: 10),

                    PaywallHero(),

                    SizedBox(height: 20),

                    PaywallFeatures(),

                    SizedBox(height: 20),

                    PaywallPlans(),

                  ],
                ),
              ),
            ),

            const PaywallPurchaseButton(),

          ],
        ),
      ),
    );
  }
}