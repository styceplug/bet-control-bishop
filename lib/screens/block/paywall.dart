import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/purchase_service.dart';
import '../../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const String _privacyPolicyUrl =
      'https://betcontrol-privacy.netlify.app';
  static const String _termsOfUseUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  bool _isLoading = true; // Start loading while we fetch RevenueCat packages
  Offerings? _offerings;
  List<StoreProduct> _fallbackProducts = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Never ask someone to pay if they already have access.
    final existing = await SubscriptionService().refreshDetails();
    if (!mounted) return;
    if (existing.isAccessGranted) {
      Navigator.pop(context, true);
      return;
    }
    await _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    try {
      Offerings offerings = await Purchases.getOfferings();
      List<StoreProduct> fallbackProducts = const [];
      if (offerings.current == null ||
          offerings.current!.availablePackages.isEmpty) {
        fallbackProducts =
            await Purchases.getProducts(PurchaseService.appleProductIds);
      }
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _fallbackProducts = fallbackProducts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch offerings: $e");
      try {
        final fallbackProducts =
            await Purchases.getProducts(PurchaseService.appleProductIds);
        if (mounted) {
          setState(() {
            _fallbackProducts = fallbackProducts;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePurchase(Package package) async {
    setState(() => _isLoading = true);

    // Pass the specific package to your updated PurchaseService
    final result = await PurchaseService().processAppleSubscription(package);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.pop(context, true); // Close paywall on success
    } else {
      // Optional: Show error snackbar using result.errorMessage
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? "Purchase failed")),
      );
    }
  }

  Future<void> _handleProductPurchase(StoreProduct product) async {
    setState(() => _isLoading = true);

    final result = await PurchaseService().processAppleStoreProduct(product);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? "Purchase failed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentOffering = _offerings?.current;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.shield_rounded,
                size: 80, color: Color(0xFF00D4AA)),
            const SizedBox(height: 20),
            Text("Go Premium",
                style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E))),
            Text("Regain control of your habits with full protection.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey)),
            const Spacer(),
            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF00D4AA))
            else if ((currentOffering == null ||
                    currentOffering.availablePackages.isEmpty) &&
                _fallbackProducts.isEmpty)
              Text("No subscription plans available.",
                  style: GoogleFonts.poppins())
            else ...[
              // Dynamically grab the Monthly package
              if (currentOffering?.monthly != null)
                _buildPlanCard(
                  "Premium Monthly",
                  currentOffering!.monthly!.storeProduct.priceString,
                  "Monthly",
                  () => _handlePurchase(currentOffering.monthly!),
                ),
              const SizedBox(height: 16),

              // Dynamically grab the Annual package
              if (currentOffering?.annual != null)
                _buildPlanCard(
                  "Premium Yearly",
                  currentOffering!.annual!.storeProduct.priceString,
                  "Yearly",
                  () => _handlePurchase(currentOffering.annual!),
                ),
              if (_fallbackProducts.isNotEmpty) ...[
                for (final product in _fallbackProducts) ...[
                  if (product != _fallbackProducts.first)
                    const SizedBox(height: 16),
                  _buildPlanCard(
                    _fallbackTitle(product),
                    product.priceString,
                    _fallbackDuration(product),
                    () => _handleProductPurchase(product),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              _buildSubscriptionLegalLinks(),
            ],
            const Spacer(),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final result =
                            await PurchaseService().restoreAppleSubscription();
                        if (!mounted) return;
                        if (result.success) {
                          navigator.pop(true);
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                result.errorMessage ??
                                    'No active subscription found.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
              child: Text("Restore Purchases",
                  style: GoogleFonts.poppins(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
      String title, String price, String sub, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFF00D4AA).withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(title,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        subtitle: Text("$sub • $price",
            style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap, // Wires the button to the purchase logic
      ),
    );
  }

  String _fallbackTitle(StoreProduct product) {
    if (product.identifier == PurchaseService.appleMonthlyProductId) {
      return 'Premium Monthly';
    }
    if (product.identifier == PurchaseService.appleAnnualProductId) {
      return 'Premium Yearly';
    }
    return product.title;
  }

  String _fallbackDuration(StoreProduct product) {
    if (product.identifier == PurchaseService.appleAnnualProductId ||
        product.subscriptionPeriod == 'P1Y') {
      return 'Yearly';
    }
    return 'Monthly';
  }

  Widget _buildSubscriptionLegalLinks() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'By subscribing you agree to our ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
        _inlineLegalLink('Privacy Policy', _privacyPolicyUrl),
        Text(
          ' and ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
        _inlineLegalLink('Terms of Use', _termsOfUseUrl),
        Text(
          '.',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _inlineLegalLink(String label, String url) {
    return GestureDetector(
      onTap: () => _openLegalUrl(url),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          color: const Color(0xFF00D4AA),
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFF00D4AA),
        ),
      ),
    );
  }

  Future<void> _openLegalUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  }
}
