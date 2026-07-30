import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/delivery_order.dart';
import 'formatters.dart';

/// Builds a printable A6 delivery label for [order]: the customer's name,
/// phone and address, plus a QR code that opens their saved location in a
/// maps app when scanned. Meant to be printed by the seller right after
/// handing the reservation to the delivery company (see DeliveryOrder /
/// ReservationViewSet.send_to_delivery on the backend).
Future<Uint8List> buildDeliveryLabelPdf(DeliveryOrder order) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Bold.ttf'),
  );

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  final mapsUrl = order.toMapsUrl;
  final isReturn = order.direction == 'return';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6.copyWith(
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
      ),
      build: (context) {
        return pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    isReturn ? 'ملصق إرجاع' : 'ملصق توصيل',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '#${order.id}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 6),
              _kv(isReturn ? 'إلى (البائع)' : 'الزبون', order.toName),
              _kv('الهاتف', order.toPhone),
              pw.SizedBox(height: 4),
              pw.Text(
                order.toAddress,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 6),
              _kv('المحتوى', '${order.itemSummary} (×${order.quantity})'),
              if (order.specialNotes.isNotEmpty)
                _kv('ملاحظات', order.specialNotes),
              if (order.cashToCollect > 0) ...[
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 1),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'مبلغ يُحصَّل نقداً',
                        style: const pw.TextStyle(fontSize: 10.5),
                      ),
                      pw.Text(
                        formatIqd(order.cashToCollect),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              pw.Spacer(),
              if (mapsUrl != null && mapsUrl.isNotEmpty)
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: mapsUrl,
                        width: 92,
                        height: 92,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'امسح الرمز لفتح موقع الزبون على الخريطة',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.Center(
                child: pw.Text(
                  isReturn ? 'من (أنت)' : 'من: ${order.fromName}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _kv(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label:  ',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}
