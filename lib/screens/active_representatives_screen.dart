import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/representative_request.dart';
import '../providers/auth_provider.dart';
import '../providers/representative_requests_provider.dart';

class ActiveRepresentativesScreen extends StatefulWidget {
  const ActiveRepresentativesScreen({super.key});

  @override
  State<ActiveRepresentativesScreen> createState() =>
      _ActiveRepresentativesScreenState();
}

class _ActiveRepresentativesScreenState
    extends State<ActiveRepresentativesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );
    await provider.loadActiveRepresentatives(accessToken: auth.accessToken!);
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = auth.user?.id;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المندوبيّات النشطة'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.handshake), text: 'أمثّل'),
              Tab(icon: Icon(Icons.assignment_ind), text: 'يمثّلونني'),
            ],
          ),
        ),
        body: Consumer<RepresentativeRequestsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingActive && provider.active.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.errorActive != null && provider.active.isEmpty) {
              return _ErrorView(message: provider.errorActive!, onRetry: _load);
            }

            final iRepresent = provider.active
                .where((r) => r.representative.id == currentUserId)
                .toList();
            final represented = provider.active
                .where((r) => r.owner.id == currentUserId)
                .toList();

            return TabBarView(
              children: [
                _RoleList(
                  list: iRepresent,
                  emptyText: 'لا تُمثّل أحداً بعد',
                  isOwnerView: false,
                  onRefresh: _load,
                ),
                _RoleList(
                  list: represented,
                  emptyText: 'لا أحد يُمثّلك بعد',
                  isOwnerView: true,
                  onRefresh: _load,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleList extends StatelessWidget {
  final List<RepresentativeRequest> list;
  final String emptyText;
  final bool isOwnerView;
  final Future<void> Function() onRefresh;

  const _RoleList({
    required this.list,
    required this.emptyText,
    required this.isOwnerView,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.handshake_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              emptyText,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final r = list[index];
          return _ActiveRepCard(
            key: ValueKey(r.id),
            representation: r,
            isOwnerView: isOwnerView,
          );
        },
      ),
    );
  }
}

class _ActiveRepCard extends StatefulWidget {
  final RepresentativeRequest representation;
  final bool isOwnerView;

  const _ActiveRepCard({
    super.key,
    required this.representation,
    required this.isOwnerView,
  });

  @override
  State<_ActiveRepCard> createState() => _ActiveRepCardState();
}

class _ActiveRepCardState extends State<_ActiveRepCard> {
  bool _isProcessing = false;

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inDays > 0) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours > 0) return 'منذ ${diff.inHours} ساعة';
    if (diff.inMinutes > 0) return 'منذ ${diff.inMinutes} دقيقة';
    return 'الآن';
  }

  Widget _permChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Text(
        label,
        style: TextStyle(color: Colors.blue[700], fontSize: 12),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          widget.isOwnerView ? 'إنهاء المندوبيّة' : 'إلغاء مندوبيّتي',
        ),
        content: Text(
          widget.isOwnerView
              ? 'هل تريد إنهاء مندوبيّة "${widget.representation.item.title}"؟ لن يستطيع ${widget.representation.representative.username} العمل كمندوب بعد ذلك.'
              : 'هل تريد إلغاء مندوبيّتك لـ "${widget.representation.item.title}"؟ لن تستطيع البيع نيابة عن ${widget.representation.owner.username} بعد ذلك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لا'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(widget.isOwnerView ? 'نعم، أنهِ' : 'نعم، ألغِ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _cancel();
  }

  Future<void> _cancel() async {
    setState(() => _isProcessing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.cancelRequest(
      accessToken: auth.accessToken!,
      requestId: widget.representation.id,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _showEditDialog() async {
    await showDialog(
      context: context,
      builder: (_) =>
          _EditPermissionsDialog(representation: widget.representation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final representation = widget.representation;
    final isOwnerView = widget.isOwnerView;
    final item = representation.item;
    final otherParty = isOwnerView
        ? representation.representative
        : representation.owner;
    final otherLabel = isOwnerView ? 'المندوب' : 'المالك';
    final image = item.firstImage;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: image != null
                      ? AppNetworkImage(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.image),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$otherLabel: ',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            otherParty.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (representation.acceptedAt != null)
                        Text(
                          'قُبِل ${_formatDate(representation.acceptedAt)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'نشط',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.percent, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Text(
                  'النسبة: ${representation.commissionPercentage.toStringAsFixed(1)} ٪',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isOwnerView ? 'صلاحيّاته' : 'صلاحيّاتي',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (representation.canList) _permChip('عرض للبيع'),
                if (representation.canNegotiate) _permChip('تفاوض'),
                if (representation.canCompleteSale) _permChip('إتمام بيع'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.isOwnerView)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _showEditDialog,
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      label: const Text(
                        'تعديل',
                        style: TextStyle(color: Colors.blue),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                if (widget.isOwnerView) const SizedBox(width: 8),
                if (representation.canCancel || !widget.isOwnerView)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _confirmCancel,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red,
                              ),
                            )
                          : const Icon(
                              Icons.stop_circle_outlined,
                              color: Colors.red,
                            ),
                      label: Text(
                        widget.isOwnerView ? 'إنهاء' : 'إلغاء',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditPermissionsDialog extends StatefulWidget {
  final RepresentativeRequest representation;
  const _EditPermissionsDialog({required this.representation});

  @override
  State<_EditPermissionsDialog> createState() => _EditPermissionsDialogState();
}

class _EditPermissionsDialogState extends State<_EditPermissionsDialog> {
  late TextEditingController _commissionController;
  late bool _canList;
  late bool _canNegotiate;
  late bool _canCompleteSale;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final r = widget.representation;
    _commissionController = TextEditingController(
      text: r.commissionPercentage.toStringAsFixed(1),
    );
    _canList = r.canList;
    _canNegotiate = r.canNegotiate;
    _canCompleteSale = r.canCompleteSale;
  }

  @override
  void dispose() {
    _commissionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final commission = double.tryParse(_commissionController.text);
    if (commission == null || commission <= 0 || commission > 100) {
      setState(() => _errorMessage = 'النسبة بين 0 و 100');
      return;
    }

    if (!_canList && !_canNegotiate && !_canCompleteSale) {
      setState(() => _errorMessage = 'اختر صلاحيّة واحدة على الأقل');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.updatePermissions(
      accessToken: auth.accessToken!,
      requestId: widget.representation.id,
      canList: _canList,
      canNegotiate: _canNegotiate,
      canCompleteSale: _canCompleteSale,
      commissionPercentage: commission,
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: Colors.green),
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل صلاحيّات المندوب'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _commissionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'النسبة (٪)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'الصلاحيّات',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            CheckboxListTile(
              value: _canList,
              onChanged: _isSubmitting
                  ? null
                  : (v) => setState(() => _canList = v ?? false),
              title: const Text('عرض للبيع'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _canNegotiate,
              onChanged: _isSubmitting
                  ? null
                  : (v) => setState(() => _canNegotiate = v ?? false),
              title: const Text('تفاوض'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _canCompleteSale,
              onChanged: _isSubmitting
                  ? null
                  : (v) => setState(() => _canCompleteSale = v ?? false),
              title: const Text('إتمام بيع'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
