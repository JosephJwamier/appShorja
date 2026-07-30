import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/delivery_order.dart';
import '../theme/app_colors.dart';
import '../utils/delivery_label_pdf.dart';

/// Lets the seller print (or share/save) an A6 delivery label for [order]:
/// the customer's name, phone and address, plus a QR code that opens their
/// saved location in a maps app when scanned. Reached from the delivery
/// order card on the reservation detail screen once the reservation has
/// been handed to the delivery company.
class PrintDeliveryLabelScreen extends StatelessWidget {
  final DeliveryOrder order;

  const PrintDeliveryLabelScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text(
            'طباعة ملصق التوصيل',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: PdfPreview(
            build: (_) => buildDeliveryLabelPdf(order),
            initialPageFormat: PdfPageFormat.a6,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: 'delivery-label-${order.id}.pdf',
          ),
        ),
      ),
    );
  }
}
