import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../services/purchase_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = true; // Start loading while we fetch RevenueCat packages
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    try {
      Offerings offerings = await Purchases.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch offerings: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePurchase(Package package) async {
    setState(() => _isLoading = true);

    // Pass the specific package to your updated PurchaseService
    final result = await PurchaseService().processAppleSubscription(package);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.pop(context); // Close paywall on success
    } else {
      // Optional: Show error snackbar using result.errorMessage
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? "Purchase failed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.shield_rounded, size: 80, color: Color(0xFF00D4AA)),
            const SizedBox(height: 20),
            Text("Go Premium", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E))),
            Text("Regain control of your habits with full protection.", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey)),
            const Spacer(),

            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF00D4AA))
            else if (_offerings?.current == null)
              Text("No subscription plans available.", style: GoogleFonts.poppins())
            else ...[
                // Dynamically grab the Monthly package
                if (_offerings!.current!.monthly != null)
                  _buildPlanCard(
                    "Monthly",
                    "₦2,000",
                    "3-day free trial",
                        () => _handlePurchase(_offerings!.current!.monthly!),
                  ),
                const SizedBox(height: 16),

                // Dynamically grab the Annual package
                if (_offerings!.current!.annual != null)
                  _buildPlanCard(
                    "Annual",
                    "₦20,000",
                    "Save 15% - Best Value",
                        () => _handlePurchase(_offerings!.current!.annual!),
                  ),
              ],

            const Spacer(),
            TextButton(
              onPressed: _isLoading ? null : () async {
                setState(() => _isLoading = true);
                try {
                  await Purchases.restorePurchases();
                  // Add logic here if restore is successful
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: Text("Restore Purchases", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(String title, String price, String sub, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00D4AA).withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        subtitle: Text("$sub • $price", style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap, // Wires the button to the purchase logic
      ),
    );
  }
}