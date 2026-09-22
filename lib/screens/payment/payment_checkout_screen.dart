import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/payment.dart';
import '../../providers/auth_provider.dart';
import '../../services/payment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// Waits for a payment to settle while the customer pays on the gateway's own
/// page.
///
/// The card is entered in an external browser, never in this app. That is the
/// whole point of the hosted-page integration: no card data crosses this
/// process, which keeps the project outside PCI-DSS scope. It also means a
/// system browser rather than an in-app WebView — customers can see the real
/// address bar and padlock, which is what makes a payment page trustworthy,
/// and card managers and 3-D Secure apps work properly there.
///
/// The result is never read from the browser. The gateway appends a `status`
/// to its return URL, but query parameters are typed by whoever holds the
/// keyboard. This screen polls the backend instead, which re-asks the gateway
/// over an authenticated channel.
class PaymentCheckoutScreen extends StatefulWidget {
  final PaymentIntent intent;

  const PaymentCheckoutScreen({super.key, required this.intent});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 3);
  // Al Qaseh's payment token expires in hours, but a customer who has not
  // finished in five minutes has almost certainly abandoned the attempt. The
  // payment itself stays open server-side either way — this only stops the
  // polling.
  static const _pollLimit = Duration(minutes: 5);

  final _service = PaymentService();

  late PaymentIntent _intent = widget.intent;
  Timer? _poller;
  DateTime? _startedAt;
  bool _openedCheckout = false;

  /// One request at a time. Returning from the browser fires a lifecycle check
  /// while the periodic tick may already be in flight, and two overlapping
  /// polls race to write [_intent] — the loser can overwrite a settled state
  /// with the stale one it started with.
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCheckout());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  /// Every cancel goes through here. Assigning a fresh timer over a live one
  /// orphans it: nothing references it any more, so `dispose` cannot cancel it
  /// and it keeps polling after the screen is gone.
  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the browser is the strongest signal that the payment
    // just finished — check immediately rather than waiting for the next tick.
    if (state == AppLifecycleState.resumed && _openedCheckout && !_intent.isFinal) {
      _checkOnce();
    }
  }

  Future<void> _openCheckout() async {
    final url = Uri.tryParse(_intent.checkoutUrl);
    if (url == null || _intent.checkoutUrl.isEmpty) {
      setState(() => _error = 'رابط الدفع غير صالح');
      return;
    }

    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      setState(() => _error = 'تعذّر فتح صفحة الدفع');
      return;
    }

    setState(() {
      _openedCheckout = true;
      _startedAt = DateTime.now();
    });

    // Reopening the checkout page must not stack a second timer on the first.
    _stopPolling();
    _poller = Timer.periodic(_pollInterval, (_) => _checkOnce());
  }

  Future<void> _checkOnce() async {
    if (_checking || _intent.isFinal) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    final startedAt = _startedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) > _pollLimit) {
      _stopPolling();
      return;
    }

    _checking = true;
    try {
      final fresh = await _service.fetchPayment(
        accessToken: token,
        reference: _intent.reference,
      );
      if (!mounted) return;
      setState(() => _intent = fresh);
      if (fresh.isFinal) {
        _stopPolling();
        // `true` means the wallet has already been credited server-side, so
        // the caller can refresh its balance.
        if (fresh.isSucceeded) Navigator.pop(context, true);
      }
    } catch (_) {
      // A dropped poll is not a failed payment — keep trying until the limit.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('إتمام الدفع')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusIcon(),
              const SizedBox(height: 20),
              Text(
                _headline,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                _detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text(
                formatIqd(_intent.amount),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),
              if (_intent.isPending && _openedCheckout) ...[
                OutlinedButton.icon(
                  onPressed: _openCheckout,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('إعادة فتح صفحة الدفع'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء والعودة'),
                ),
              ],
              if (_intent.isFinal && !_intent.isSucceeded)
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('عودة'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (_error != null || (_intent.isFinal && !_intent.isSucceeded)) {
      return const Icon(Icons.error_outline, size: 64, color: AppColors.error);
    }
    if (_intent.isSucceeded) {
      return const Icon(Icons.check_circle_outline, size: 64, color: AppColors.success);
    }
    return const SizedBox(
      width: 56,
      height: 56,
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  String get _headline {
    if (_error != null) return _error!;
    if (_intent.isSucceeded) return 'تم الدفع بنجاح';
    if (_intent.state == 'cancelled') return 'أُلغيت العملية';
    if (_intent.isFinal) return 'لم تكتمل عملية الدفع';
    return 'بانتظار إتمام الدفع';
  }

  String get _detail {
    if (_intent.isSucceeded) return 'أُضيف المبلغ إلى رصيد محفظتك';
    if (_intent.isFinal) {
      return _intent.failureReason.isNotEmpty
          ? _intent.failureReason
          : 'لم يُخصم أي مبلغ. يمكنك المحاولة مرة أخرى';
    }
    return 'أكمل الدفع في المتصفّح ثم عُد إلى التطبيق.\n'
        'سنتحقّق من العملية تلقائياً.';
  }
}
