import 'package:flutter/material.dart';

import '../../models/payment.dart';
import '../../theme/app_colors.dart';

/// Lets the customer choose which gateway to pay with.
///
/// The list is whatever the server returned — this sheet has no knowledge of
/// any specific provider. When a second gateway is configured it appears here
/// with no app change; that is the reason the picker exists now, while there
/// is only one method to pick.
///
/// With exactly one method the sheet still shows, rather than silently using
/// it: the customer should see what they are about to pay with.
Future<PaymentMethod?> showPaymentMethodSheet(
  BuildContext context, {
  required List<PaymentMethod> methods,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'اختر طريقة الدفع',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (methods.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد طريقة دفع متاحة حالياً',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ...methods.map(
                (method) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryContainer,
                    child: Icon(Icons.credit_card, color: Colors.white, size: 20),
                  ),
                  title: Text(method.labelAr),
                  subtitle: Text(method.currencies.join('، ')),
                  trailing: const Icon(Icons.chevron_left,
                      color: AppColors.onSurfaceVariant),
                  onTap: () => Navigator.pop(context, method),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}
