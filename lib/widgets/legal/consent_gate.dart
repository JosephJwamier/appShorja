import 'package:flutter/material.dart';

import '../../models/legal_document.dart';
import '../../services/legal_service.dart';
import '../../theme/app_colors.dart';

/// يغلّف الشاشة الرئيسية بعد تسجيل الدخول: يتحقّق من وجود شروط/سياسة تنتظر
/// موافقة المستخدم، وإن وُجدت يعرض طبقة إلزامية غير قابلة للتجاهل حتى يوافق.
/// (يُلبّي متطلّب: موافقة إلزامية عند التسجيل + إعادة الموافقة عند التحديث.)
class ConsentGate extends StatefulWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  final _service = LegalService();

  bool _checked = false;
  bool _mustAccept = false;
  bool _agree = false;
  bool _submitting = false;
  List<LegalDocument> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      final pending = await _service.fetchPending(lang: 'ar');
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _mustAccept = pending.isNotEmpty;
        _checked = true;
      });
    } catch (_) {
      // فشل الشبكة: لا نُقفل التطبيق على المستخدم (fail-open) — ستُعاد
      // المحاولة في الجلسة التالية.
      if (mounted) setState(() => _checked = true);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await _service.accept(
      lang: 'ar',
      ids: _pending.map((d) => d.id).toList(),
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _mustAccept = false;
        _submitting = false;
      });
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الموافقة، حاول مرة أخرى')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_checked && _mustAccept) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(color: Colors.black54, dismissible: false),
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              color: AppColors.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'الموافقة على الشروط والسياسة',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'لمواصلة استخدام الشورجة، يرجى الاطلاع والموافقة على المستندات التالية:',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      ..._pending.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _service.openPage(d.docType, lang: d.language),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Align(
                              alignment: Alignment.centerRight,
                              child: Text(d.title),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => setState(() => _agree = !_agree),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _agree,
                              onChanged: (v) =>
                                  setState(() => _agree = v ?? false),
                              activeColor: AppColors.primary,
                            ),
                            const Expanded(
                              child: Text(
                                'أطّلعت وأوافق على سياسة الخصوصية وشروط الاستخدام',
                                style: TextStyle(color: AppColors.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              (!_agree || _submitting) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'متابعة',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
