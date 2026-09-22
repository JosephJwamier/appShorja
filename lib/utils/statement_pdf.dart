import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ledger.dart';
import 'formatters.dart';

/// كشف حساب as an A4 PDF the merchant can hand or WhatsApp to the
/// customer: every non-void line with the running balance, and the open
/// amount in big type at the bottom. Same Amiri font as the delivery label.
Future<Uint8List> buildStatementPdf({
  required String storeName,
  required ContactStatement statement,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

  final c = statement.contact;
  final isCustomer = c.kind == ContactKind.customer;
  final now = DateTime.now();

  String date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('كشف حساب', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text(storeName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('${isCustomer ? 'الزبون' : 'المورّد'}: ${c.name}${c.phone.isEmpty ? '' : '  —  ${c.phone}'}',
            style: const pw.TextStyle(fontSize: 12)),
        pw.Text('بتاريخ ${date(now)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          cellStyle: const pw.TextStyle(fontSize: 10.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
          },
          headers: ['التاريخ', 'البيان', isCustomer ? 'عليه' : 'له', isCustomer ? 'له' : 'عليه', 'الرصيد'],
          data: [
            for (final row in statement.rows)
              [
                date(row.entry.occurredAt),
                _description(row.entry),
                _isUp(row.entry) ? formatNum(row.entry.amount) : '',
                _isUp(row.entry) ? '' : formatNum(row.entry.amount),
                formatNum(row.runningBalance),
              ],
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                statement.balance > 0
                    ? (isCustomer ? 'المبلغ المتبقّي عليه' : 'المبلغ المتبقّي له')
                    : statement.balance < 0
                        ? (isCustomer ? 'رصيد له' : 'رصيد لك')
                        : 'الحساب مسدَّد',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('${formatNum(statement.balance.abs())} IQD',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

bool _isUp(LedgerEntry e) => e.kind == LedgerKind.saleCredit || e.kind == LedgerKind.purchase;

String _description(LedgerEntry e) {
  final parts = <String>[e.kind.label];
  if (e.itemTitle != null && e.itemTitle!.isNotEmpty) {
    var s = e.itemTitle!;
    if (e.variantLabel != null && e.variantLabel!.isNotEmpty) s += ' — ${e.variantLabel}';
    if (e.quantity != null && e.quantity! > 1) s += ' ×${e.quantity}';
    parts.add(s);
  }
  if (e.note.isNotEmpty) parts.add(e.note);
  return parts.join(' · ');
}
