import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reservation.dart';
import '../models/delivery_order.dart';
import '../models/dispute.dart';
import '../providers/auth_provider.dart';
import '../providers/reservations_badge_provider.dart';
import '../services/delivery_service.dart';
import '../services/item_service.dart';
import '../services/reservation_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/refreshable_tab.dart';
import '../features/location/providers/location_provider.dart';
import '../features/location/screens/add_edit_location_screen.dart';
import '../features/location/screens/location_picker_sheet.dart';
import 'file_dispute_screen.dart';
import 'disputes_screen.dart';
import 'print_delivery_label_screen.dart';
import 'product_details_screen.dart';
import 'reservation_detail_screen.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen>
    with SingleTickerProviderStateMixin
    implements RefreshableTab {
  late final TabController _tabController;
  List<Reservation> _all = [];
  bool _isLoading = true;
  String? _error;
  int _currentUserId = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshTab() => _load();

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      _currentUserId = auth.user?.id ?? -1;
      final list = await ReservationService().fetchReservations(
        accessToken: auth.accessToken!,
      );
      if (mounted) setState(() => _all = list);
      if (mounted) {
        context.read<ReservationsBadgeProvider>().applyReservations(
              list,
              currentUserId: _currentUserId,
            );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Reservation> get _iReserved =>
      _all.where((r) => r.buyer.id == _currentUserId).toList();

  List<Reservation> get _reservedOnMine =>
      _all.where((r) => r.item.owner.id == _currentUserId).toList();

  Future<void> _complete(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    // Reservations created without a delivery address at the time (e.g. an
    // automatic auction-win reservation — see auction_utils.create_winner_
    // reservation on the backend) must have one attached before they can be
    // completed. Reuse the buyer's saved address silently, same as the live-
    // stream reserve flow — only interrupt with the add-address screen if
    // they have none at all.
    int? deliveryLocationId;
    if (r.deliveryLocation == null) {
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      await locationProvider.loadMyLocations(auth.accessToken!);
      if (!mounted) return;

      if (locationProvider.myLocations.isNotEmpty) {
        deliveryLocationId = locationProvider.myLocations.first.id;
      } else {
        final added = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const AddEditLocationScreen()),
        );
        if (!mounted) return;
        if (added != true || locationProvider.myLocations.isEmpty) return;
        deliveryLocationId = locationProvider.myLocations.first.id;
      }
    }

    final paymentType = await _pickPaymentType(r);
    if (paymentType == null) return;

    try {
      await ReservationService().completeReservation(
        accessToken: auth.accessToken!,
        reservationId: r.id,
        paymentType: paymentType,
        deliveryLocationId: deliveryLocationId,
        value: paymentType == 'deposit' ? r.depositAmount : r.totalPrice,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            paymentType != 'deposit'
                ? 'تم إكمال الحجز ودفع كامل المبلغ'
                : r.depositAmount > 0
                    ? 'تم دفع العربون — الباقي كاش عند التوصيل'
                    : 'تم تأكيد الحجز — كامل المبلغ كاش عند التوصيل',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Buyer explicitly wants to change the address (not the silent auto-pick
  /// used at reserve/complete time) — show the full picker so they can
  /// choose a different saved address or add a new one.
  Future<void> _updateDeliveryLocation(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    final loc = await showLocationPickerSheet(
      context,
      token: auth.accessToken!,
      title: 'اختر عنوان التسليم الجديد',
    );
    if (!mounted || loc == null) return;

    try {
      await ReservationService().updateDeliveryLocation(
        accessToken: auth.accessToken!,
        reservationId: r.id,
        deliveryLocationId: loc.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تعديل عنوان التوصيل'), backgroundColor: AppColors.success),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  static const _paymentExplainerSeenKey = 'has_seen_payment_explainer';

  /// One-time, slightly more detailed explanation of عربون/دفع كامل/الحماية
  /// shown the very first time a buyer reaches this decision — before that,
  /// nothing in the app explains why part of the price might be cash-on-
  /// delivery or why a full payment doesn't reach the seller immediately.
  /// Shown at most once per install; the normal fast picker below covers
  /// every time after that.
  Future<void> _maybeShowPaymentExplainer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_paymentExplainerSeenKey) ?? false) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('طريقة الدفع والتسليم'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'عربون فقط: تدفع نسبة بسيطة الآن لحجز المنتج، والباقي كاش لمندوب '
              'التوصيل عند استلامك الفعلي للمنتج.',
            ),
            SizedBox(height: 10),
            Text('دفع كامل: تدفع المبلغ بالكامل الآن داخل التطبيق.'),
            SizedBox(height: 10),
            Text(
              'بكلا الحالتين، المبلغ المدفوع بالتطبيق يبقى محفوظًا بأمان ولا '
              'يصل للبائع إلا بعد تأكيدك استلام المنتج بحالة جيدة (أو تلقائيًا '
              'خلال مدة الضمان التي يحددها البائع لكل منتج إن لم يكن هناك أي '
              'مشكلة).',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت، تابع'),
          ),
        ],
      ),
    );
    await prefs.setBool(_paymentExplainerSeenKey, true);
  }

  /// Returns 'deposit', 'full', or null if the user cancelled.
  Future<String?> _pickPaymentType(Reservation r) async {
    await _maybeShowPaymentExplainer();
    if (!mounted) return null;
    if (r.depositAmount <= 0) {
      // Seller chose not to take any deposit on this listing — buyer can
      // either pay nothing now (full amount collected in cash at delivery)
      // or pay in full immediately if they'd rather not handle cash.
      return showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('طريقة الدفع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لإكمال حجز "${r.item.title}"، اختر طريقة الدفع:'),
              const SizedBox(height: 12),
              const Text(
                'الدفع عند الاستلام: لا شيء الآن',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '(كامل المبلغ ${formatIqd(r.totalPrice)} كاش عند التوصيل)',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'أو الدفع الآن كاملاً: ${formatIqd(r.totalPrice)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'deposit'),
              child: const Text('الدفع عند الاستلام'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'full'),
              child: const Text(
                'ادفع كاملاً',
                style: TextStyle(color: AppColors.success),
              ),
            ),
          ],
        ),
      );
    }

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('طريقة الدفع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('لإكمال حجز "${r.item.title}"، اختر طريقة الدفع:'),
            const SizedBox(height: 12),
            Text(
              'عربون فقط: ${formatIqd(r.depositAmount)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '(الباقي ${formatIqd(r.totalPrice - r.depositAmount)} كاش عند التوصيل)',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أو السعر كاملاً: ${formatIqd(r.totalPrice)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'deposit'),
            child: const Text('عربون فقط'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'full'),
            child: const Text('كامل المبلغ'),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد استلام المنتج'),
        content: Text(
          'بتأكيدك استلام "${r.item.title}"، سيتم تحرير المبلغ إلى البائع فوراً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'نعم، تم الاستلام',
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ReservationService().approveAndReleasePayment(
        accessToken: auth.accessToken!,
        reservationId: r.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم تأكيد الاستلام وتحويل المبلغ إلى البائع'),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _requestPaymentRelease(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReservationService().requestPaymentRelease(
        accessToken: auth.accessToken!,
        reservationId: r.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم إرسال طلب تحرير الدفعة إلى المشتري'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _cancel(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء الحجز'),
        content: Text('هل تريد إلغاء حجز "${r.item.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'نعم، إلغِ',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ReservationService().cancelReservation(
        accessToken: auth.accessToken!,
        reservationId: r.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء الحجز'),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _sendToDelivery(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إسناد التوصيل لشركة التوصيل'),
        content: Text(
          'سيتم تسليم "${r.item.title}" لشركة التوصيل لتتولى إيصاله للمشتري.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إسناد التوصيل'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DeliveryService().sendToDelivery(
        accessToken: auth.accessToken!,
        reservationId: r.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم إسناد التوصيل لشركة التوصيل'),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _sendToDeliveryBatch(List<Reservation> reservations) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('دمج التوصيل'),
        content: Text(
          'سيتم تسليم ${reservations.length} منتجات لشركة التوصيل معاً كرحلة واحدة (أو أكثر لو تجاوزت الحجم المسموح)، وسيُرد للمشتري فرق رسوم التوصيل الزائدة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('دمج التوصيل'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final result = await DeliveryService().sendToDeliveryBatch(
        accessToken: auth.accessToken!,
        reservationIds: reservations.map((r) => r.id).toList(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.trips == 1
                ? 'تم دمج التوصيل برحلة واحدة'
                : 'تجاوز الحجم المسموح — تم تقسيمها إلى ${result.trips} رحلات توصيل',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmDeliveryReceipt(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد استلام المنتج'),
        content: Text(
          'بتأكيدك استلام "${r.item.title}"، سيبقى المبلغ محجوزاً ويُحرَّر للبائع '
          'تلقائياً خلال ${formatDaysAr(r.warrantyDays)} — أو يمكنك تحريره الآن '
          'بنفسك إن لم تكن لديك أي مشكلة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'نعم، تم الاستلام',
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DeliveryService().confirmReceipt(
        accessToken: auth.accessToken!,
        deliveryOrderId: r.deliveryOrder!.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'تم تأكيد الاستلام — سيُحرَّر المبلغ للبائع خلال ${formatDaysAr(r.warrantyDays)} أو عند موافقتك',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _refuseDeliveryReceipt(Reservation r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final reasonController = TextEditingController();
    final forfeited = r.depositAmount + (r.isDepositOnly ? 0 : r.deliveryFee);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رفض استلام المنتج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إذا كانت لديك مشكلة حقيقية بـ"${r.item.title}" (تالف، مختلف عمّا طلبت...)، اكتبها أدناه — ستتم مراجعتها من فريق الدعم وقد تسترد كامل مبلغك.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'وصف المشكلة (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Text(
              'بدون وصف مشكلة، سيُعتبر رفضاً بلا سبب: يُخصَم العربون ${formatIqd(r.depositAmount)}'
              '${r.isDepositOnly ? '' : ' وأجور التوصيل ${formatIqd(r.deliveryFee)}'} '
              '(الإجمالي ${formatIqd(forfeited)})، ويُعاد الباقي بعد استلام الشركة للمنتج منك.',
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'رفض الاستلام',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final message = await DeliveryService().refuseReceipt(
        accessToken: auth.accessToken!,
        deliveryOrderId: r.deliveryOrder!.id,
        reason: reasonController.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.success),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // الشاشة مدفوعة فوق MainShell (الذي يُبنى بدون Directionality صريح، أي
    // LTR افتراضيًا) — لذا نغلّف الشاشة بالكامل بـ RTL هنا صراحةً ليتطابق
    // ترتيب العناصر مع تصميم عربي سليم.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'حجوزاتي',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        automaticallyImplyLeading: false,
        // Only show a back arrow when this was pushed on top of something
        // (from a notification tap, product details, etc.) — as a MainShell
        // bottom-nav tab there's nothing to pop back to.
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('حجزت عليها'),
                  if (!_isLoading && _iReserved.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _Badge(_iReserved.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.storefront_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('منتجاتي المحجوزة'),
                  if (!_isLoading && _reservedOnMine.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _Badge(_reservedOnMine.length),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _ReservationsList(
                  reservations: _iReserved,
                  emptyMessage: 'لم تقم بأي حجز بعد',
                  currentUserId: _currentUserId,
                  onComplete: _complete,
                  onCancel: _cancel,
                  onApprove: _approve,
                  onRequestPaymentRelease: _requestPaymentRelease,
                  onSendToDelivery: _sendToDelivery,
                  onConfirmDeliveryReceipt: _confirmDeliveryReceipt,
                  onRefuseDeliveryReceipt: _refuseDeliveryReceipt,
                  onUpdateDeliveryLocation: _updateDeliveryLocation,
                  onRefresh: _load,
                ),
                _ReservationsList(
                  reservations: _reservedOnMine,
                  emptyMessage: 'لا توجد حجوزات على منتجاتك',
                  currentUserId: _currentUserId,
                  onComplete: _complete,
                  onCancel: _cancel,
                  onApprove: _approve,
                  onRequestPaymentRelease: _requestPaymentRelease,
                  onSendToDelivery: _sendToDelivery,
                  onConfirmDeliveryReceipt: _confirmDeliveryReceipt,
                  onRefuseDeliveryReceipt: _refuseDeliveryReceipt,
                  onUpdateDeliveryLocation: _updateDeliveryLocation,
                  onRefresh: _load,
                  allowCombine: true,
                  onSendToDeliveryBatch: _sendToDeliveryBatch,
                ),
              ],
            ),
    );
  }
}

// ── قائمة الحجوزات مع فلاتر ──────────────────────────────────────────────────
class _ReservationsList extends StatefulWidget {
  final List<Reservation> reservations;
  final String emptyMessage;
  final int currentUserId;
  final Future<void> Function(Reservation) onComplete;
  final Future<void> Function(Reservation) onCancel;
  final Future<void> Function(Reservation) onApprove;
  final Future<void> Function(Reservation) onRequestPaymentRelease;
  final Future<void> Function(Reservation) onSendToDelivery;
  final Future<void> Function(Reservation) onConfirmDeliveryReceipt;
  final Future<void> Function(Reservation) onRefuseDeliveryReceipt;
  final Future<void> Function(Reservation) onUpdateDeliveryLocation;
  final Future<void> Function() onRefresh;
  // Only meaningful for the seller's "منتجاتي المحجوزة" tab — lets several
  // eligible reservations be selected and sent to delivery together as one
  // trip (or a few, if they exceed the size cap) instead of one at a time.
  final bool allowCombine;
  final Future<void> Function(List<Reservation>)? onSendToDeliveryBatch;

  const _ReservationsList({
    required this.reservations,
    required this.emptyMessage,
    required this.currentUserId,
    required this.onComplete,
    required this.onCancel,
    required this.onApprove,
    required this.onRequestPaymentRelease,
    required this.onSendToDelivery,
    required this.onConfirmDeliveryReceipt,
    required this.onRefuseDeliveryReceipt,
    required this.onUpdateDeliveryLocation,
    required this.onRefresh,
    this.allowCombine = false,
    this.onSendToDeliveryBatch,
  });

  @override
  State<_ReservationsList> createState() => _ReservationsListState();
}

class _ReservationsListState extends State<_ReservationsList> {
  String _filter = 'all';
  bool _combineMode = false;
  final Set<int> _selectedIds = {};

  static const _filters = [
    ('all', 'الكل'),
    ('pending', 'انتظار'),
    ('completed', 'مكتملة'),
    ('confirmed', 'مؤكد'),
    ('cancelled', 'ملغية'),
  ];

  List<Reservation> get _filtered {
    if (_filter == 'all') return widget.reservations;
    // 'confirmed' is its own tab now — 'completed' (paid, awaiting delivery
    // or buyer confirmation) and 'confirmed' (settled) are distinct stages,
    // so they no longer get merged into one tab.
    return widget.reservations.where((r) => r.status == _filter).toList();
  }

  List<Reservation> get _selectedReservations =>
      widget.reservations.where((r) => _selectedIds.contains(r.id)).toList();

  /// The first-selected reservation pins the buyer/address the rest must
  /// match — combining only makes sense for one physical trip.
  Reservation? get _anchor =>
      _selectedIds.isEmpty ? null : _selectedReservations.first;

  bool _canSelectForCombine(Reservation r) {
    if (!r.canSendToDelivery) return false;
    final anchor = _anchor;
    if (anchor == null) return true;
    return r.buyer.id == anchor.buyer.id &&
        r.deliveryLocation?.id == anchor.deliveryLocation?.id;
  }

  void _toggleCombineMode() {
    setState(() {
      _combineMode = !_combineMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(Reservation r) {
    if (!_canSelectForCombine(r) && !_selectedIds.contains(r.id)) return;
    setState(() {
      if (!_selectedIds.remove(r.id)) _selectedIds.add(r.id);
    });
  }

  Future<void> _confirmCombine() async {
    final reservations = _selectedReservations;
    if (reservations.length < 2 || widget.onSendToDeliveryBatch == null) {
      return;
    }
    await widget.onSendToDeliveryBatch!(reservations);
    if (mounted) setState(() => _combineMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Column(
      children: [
        // شريط الفلاتر
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                  children: _filters.map((f) {
              final (key, label) = f;
              final count = key == 'all'
                  ? widget.reservations.length
                  : widget.reservations.where((r) => r.status == key).length;
              final selected = _filter == key;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 0 ? '$label  $count' : label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
                  }).toList(),
                  ),
                ),
              ),
              if (widget.allowCombine)
                IconButton(
                  tooltip: _combineMode ? 'إلغاء الدمج' : 'دمج التوصيل',
                  icon: Icon(
                    _combineMode ? Icons.close_rounded : Icons.merge_type_rounded,
                    color: _combineMode
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                  onPressed: _toggleCombineMode,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // القائمة
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 56,
                        color: AppColors.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _filter == 'all'
                            ? widget.emptyMessage
                            : 'لا توجد حجوزات في هذا القسم',
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ReservationCard(
                      r: list[i],
                      currentUserId: widget.currentUserId,
                      onComplete: widget.onComplete,
                      onCancel: widget.onCancel,
                      onApprove: widget.onApprove,
                      onRequestPaymentRelease: widget.onRequestPaymentRelease,
                      onSendToDelivery: widget.onSendToDelivery,
                      onConfirmDeliveryReceipt: widget.onConfirmDeliveryReceipt,
                      onRefuseDeliveryReceipt: widget.onRefuseDeliveryReceipt,
                      onUpdateDeliveryLocation: widget.onUpdateDeliveryLocation,
                      onRefresh: widget.onRefresh,
                      combineMode: _combineMode,
                      isSelectedForCombine: _selectedIds.contains(list[i].id),
                      canSelectForCombine: _canSelectForCombine(list[i]),
                      onToggleSelectForCombine: _toggleSelected,
                    ),
                  ),
                ),
        ),
        if (_combineMode && _selectedIds.length >= 2)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _confirmCombine,
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text('دمج التوصيل (${_selectedIds.length})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── بطاقة الحجز ──────────────────────────────────────────────────────────────
class _ReservationCard extends StatelessWidget {
  final Reservation r;
  final int currentUserId;
  final Future<void> Function(Reservation) onComplete;
  final Future<void> Function(Reservation) onCancel;
  final Future<void> Function(Reservation) onApprove;
  final Future<void> Function(Reservation) onRequestPaymentRelease;
  final Future<void> Function(Reservation) onSendToDelivery;
  final Future<void> Function(Reservation) onConfirmDeliveryReceipt;
  final Future<void> Function(Reservation) onRefuseDeliveryReceipt;
  final Future<void> Function(Reservation) onUpdateDeliveryLocation;
  final Future<void> Function() onRefresh;
  final bool combineMode;
  final bool isSelectedForCombine;
  final bool canSelectForCombine;
  final ValueChanged<Reservation>? onToggleSelectForCombine;
  const _ReservationCard({
    required this.r,
    required this.currentUserId,
    required this.onComplete,
    required this.onCancel,
    required this.onApprove,
    required this.onRequestPaymentRelease,
    required this.onSendToDelivery,
    required this.onConfirmDeliveryReceipt,
    required this.onRefuseDeliveryReceipt,
    required this.onUpdateDeliveryLocation,
    required this.onRefresh,
    this.combineMode = false,
    this.isSelectedForCombine = false,
    this.canSelectForCombine = false,
    this.onToggleSelectForCombine,
  });

  Future<void> _reportProblem(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FileDisputeScreen(reservation: r)),
    );
    if (result == true) await onRefresh();
  }

  /// One-tap re-order: opens the same item's current listing straight on
  /// product details, ready to reserve again — shortens the gap between a
  /// buyer's first and second order on something they already trust.
  Future<void> _orderAgain(BuildContext context) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final listing = await ItemService().fetchListingByItemId(
        accessToken: token,
        itemId: r.item.id,
      );
      navigator.pop();
      if (listing != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(listing: listing),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('هذا المنتج لم يعد متوفراً')),
        );
      }
    } catch (_) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر فتح تفاصيل المنتج')),
      );
    }
  }

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReservationDetailScreen(
          reservation: r,
          currentUserId: currentUserId,
          onComplete: onComplete,
          onCancel: onCancel,
          onApprove: onApprove,
          onRequestPaymentRelease: onRequestPaymentRelease,
          onSendToDelivery: onSendToDelivery,
          onConfirmDeliveryReceipt: onConfirmDeliveryReceipt,
          onRefuseDeliveryReceipt: onRefuseDeliveryReceipt,
          onUpdateDeliveryLocation: onUpdateDeliveryLocation,
          onRefresh: onRefresh,
        ),
      ),
    );
  }

  ({Color bg, Color fg, IconData icon, String label}) _statusStyle() {
    switch (r.status) {
      case 'pending':
        return (
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
          icon: Icons.hourglass_top_rounded,
          label: 'بانتظار الاكمال',
        );
      case 'confirmed':
        return (
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
          icon: Icons.verified_outlined,
          label: 'مؤكّد',
        );
      case 'completed':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          icon: Icons.check_circle_outline,
          label: 'مكتمل',
        );
      case 'cancelled':
        return (
          bg: const Color(0xFFFFEBEE),
          fg: AppColors.error,
          icon: Icons.cancel_outlined,
          label: 'ملغى',
        );
      default:
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.info_outline,
          label: r.status,
        );
    }
  }

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}';
  }

  String _timeRemaining() {
    final h = r.timeRemaining ~/ 3600;
    final m = (r.timeRemaining % 3600) ~/ 60;
    if (h >= 24) return '${h ~/ 24} يوم متبقي';
    if (h > 0) return '$h س $m د متبقية';
    return '$m دقيقة متبقية';
  }

  String _deliveryStatusLabel(DeliveryOrder order) {
    final prefix = order.isMerged ? '🔗 مدموج — ' : '';
    if (order.direction == 'return') {
      switch (order.status) {
        case 'assigned':
          return '$prefixإرجاع للبائع — بانتظار استلام الشركة من المشتري';
        case 'picked_up':
        case 'delivered':
          return '$prefixاستلمت الشركة المنتج — تم استرداد المبلغ';
        default:
          return '$prefixإرجاع للبائع';
      }
    }
    switch (order.status) {
      case 'assigned':
        return '$prefixتم إسناد التوصيل — بانتظار استلام الشركة';
      case 'picked_up':
        return '$prefixاستلمت الشركة المنتج — بالطريق إليك';
      case 'delivered':
        return prefix +
            (order.cashCollected
                ? 'وصل المنتج وتم تحصيل الباقي نقداً — بانتظار تأكيد المشتري'
                : 'وصل المنتج — بانتظار تأكيد المشتري');
      case 'confirmed':
        return '$prefixأكّد المشتري الاستلام';
      case 'refused':
        return '$prefixرفض المشتري الاستلام';
      default:
        return '$prefixقيد التوصيل';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _statusStyle();
    final image = r.item.firstImage;
    final isBuyer = r.buyer.id == currentUserId;
    // Only a still-'pending' reservation is waiting to be paid (and subject
    // to the hold expiring). Paying to complete the reservation is a
    // buyer-only action.
    final canComplete = isBuyer && r.status == 'pending';
    // Backend-computed: seller, payment still held. The backend flag alone
    // doesn't check delivery-company progress, so gate it further here so
    // the seller can only nudge the buyer once the item has actually
    // reached them (deliveryOrder.deliveredAt set), not while it's still
    // assigned/picked-up/in transit.
    final canRequestPaymentRelease = r.canRequestPaymentRelease &&
        (r.deliveryOrder == null || r.deliveryOrder!.deliveredAt != null);
    // Remainder is only outstanding while still 'completed' (paid deposit,
    // awaiting delivery/confirmation) and not yet collected by the delivery
    // company — once collected, amountCharged (from the backend) already
    // includes it, so remainingCashOnDelivery drops to 0 on its own.
    final awaitingCashOnDelivery = r.status == 'completed' &&
        r.isDepositOnly &&
        r.remainingCashOnDelivery > 0;
    // In combine mode, a reservation that can't join the current selection
    // (wrong buyer/address, or not eligible for delivery yet) is dimmed and
    // untappable rather than hidden — the seller can still see it's there.
    final combineDisabled =
        combineMode && !canSelectForCombine && !isSelectedForCombine;

    return Opacity(
      opacity: combineDisabled ? 0.4 : 1,
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: combineMode
            ? (combineDisabled ? null : () => onToggleSelectForCombine?.call(r))
            : () => _openDetail(context),
        child: Container(
          decoration: BoxDecoration(
            color: isSelectedForCombine
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelectedForCombine
                  ? AppColors.primary
                  : AppColors.surfaceContainer,
              width: isSelectedForCombine ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // الهيدر: صورة + معلومات أساسية
              Row(
                children: [
                  if (combineMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: isSelectedForCombine,
                        onChanged: combineDisabled
                            ? null
                            : (_) => onToggleSelectForCombine?.call(r),
                      ),
                    ),
                  // الصورة
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: image != null
                          ? AppNetworkImage(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  // المعلومات
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // شارة الحالة
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: s.bg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(s.icon, size: 12, color: s.fg),
                                const SizedBox(width: 4),
                                Text(
                                  s.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: s.fg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            r.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'البائع: ${r.item.owner.username}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _PriceChip(
                                label: 'عربون',
                                value: formatIqd(r.depositAmount),
                              ),
                              _PriceChip(
                                label: 'إجمالي',
                                value: formatIqd(r.totalPrice),
                              ),
                              // The seller's own line: what reaches their
                              // wallet after the platform's cut (and the
                              // representative's, if any). Buyers don't
                              // need it — they pay the total.
                              if (!isBuyer && r.platformCommissionAmount > 0)
                                _PriceChip(
                                  label: 'صافيك بعد العمولة ${r.platformCommissionPercent.toStringAsFixed(r.platformCommissionPercent % 1 == 0 ? 0 : 1)}%',
                                  value: formatIqd(r.sellerNet),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // شريط التفاصيل السفلي
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ينتهي ${_formatDate(r.expiresAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (canComplete) ...[
                          const Spacer(),
                          const Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _timeRemaining(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (awaitingCashOnDelivery) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'الباقي ${formatIqd(r.remainingCashOnDelivery)} كاش عند التوصيل',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (r.deliveryOrder != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.local_shipping_outlined,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _deliveryStatusLabel(r.deliveryOrder!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (canComplete || r.canCancel) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (canComplete)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => onComplete(r),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                ),
                                label: const Text('إكمال'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          if (canComplete && r.canCancel)
                            const SizedBox(width: 8),
                          if (r.canCancel)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => onCancel(r),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('إلغاء'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: AppColors.error,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (r.hasDispute) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DisputesScreen(),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.gavel_outlined,
                                size: 14,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'نزاع ${disputeStatusLabel(r.disputeStatus ?? 'open')} — عرض التفاصيل',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Buyer: the sale is fully settled — one-tap re-order
                      // straight onto product details, ready to reserve again.
                      if (isBuyer && r.status == 'confirmed') ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _orderAgain(context),
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('اطلبه مرة ثانية'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Only the buyer may confirm receipt — this is what
                      // releases the held payment to the seller (or it releases
                      // automatically after the item's warranty period with no
                      // dispute).
                      if (r.canApprove) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => onApprove(r),
                            icon: const Icon(Icons.verified_outlined, size: 16),
                            label: const Text('تم التأكد من المنتج'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Only the seller may nudge the buyer to release payment —
                      // sends the buyer a notification with its own confirm button.
                      if (canRequestPaymentRelease) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => onRequestPaymentRelease(r),
                            icon: const Icon(Icons.campaign_outlined, size: 16),
                            label: const Text('طلب تحرير الدفعة من المشتري'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Seller: hand a paid order off to the delivery company
                      // instead of (or before) cancelling it.
                      if (r.canSendToDelivery) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => onSendToDelivery(r),
                            icon: const Icon(
                              Icons.local_shipping_outlined,
                              size: 16,
                            ),
                            label: const Text('إسناد التوصيل لشركة التوصيل'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Seller: print an A6 label with the buyer's address
                      // and a QR code that opens their location on a maps
                      // app — only useful before the company actually picks
                      // the item up, so it disappears once they have.
                      if (!isBuyer &&
                          r.deliveryOrder != null &&
                          r.deliveryOrder!.isOutbound &&
                          r.deliveryOrder!.status == 'assigned') ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PrintDeliveryLabelScreen(
                                  order: r.deliveryOrder!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.print_outlined, size: 16),
                            label: const Text('طباعة ملصق التوصيل'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Buyer: the item has physically arrived — confirm or
                      // refuse it (mirrors the "delivery_arrived" push
                      // notification's inline actions). awaitingReceiptDecision
                      // is purely status-based (no role check), so isBuyer
                      // must be checked here or the seller sees it too.
                      if (isBuyer &&
                          r.deliveryOrder?.awaitingReceiptDecision ==
                              true) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => onConfirmDeliveryReceipt(r),
                                icon: const Icon(
                                  Icons.verified_outlined,
                                  size: 16,
                                ),
                                label: const Text('تم الاستلام'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => onRefuseDeliveryReceipt(r),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('رفض الاستلام'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: AppColors.error,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Disputes are only accepted by the server while
                      // 'completed' — the window before the sale is settled to
                      // 'confirmed' (see ReservationViewSet.create_dispute).
                      if (r.status == 'completed') ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _reportProblem(context),
                          icon: const Icon(
                            Icons.report_gmailerrorred_outlined,
                            size: 15,
                          ),
                          label: const Text('الإبلاغ عن مشكلة'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceContainer,
    child: const Icon(Icons.image, size: 36, color: AppColors.outline),
  );
}

class _PriceChip extends StatelessWidget {
  final String label;
  final String value;
  const _PriceChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.primaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
