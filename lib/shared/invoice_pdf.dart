import 'dart:typed_data';

import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app.dart';
import '../core/data.dart';

// ألوان البراند
const _black = PdfColor(0.039, 0.039, 0.039);
const _gold = PdfColor(0.788, 0.647, 0.298);
const _goldLight = PdfColor(0.965, 0.937, 0.863);
const _grey = PdfColor(0.42, 0.42, 0.42);
const _line = PdfColor(0.886, 0.863, 0.796);
const _red = PdfColor(0.753, 0.224, 0.169);
const _green = PdfColor(0.118, 0.518, 0.286);

pw.Font? _regular, _bold;
pw.MemoryImage? _logo;

Future<void> _loadAssets() async {
  _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  _logo ??= pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
}

/// نص عربي (يمين لشمال)
pw.Widget _t(String s,
    {double size = 10,
    bool bold = false,
    PdfColor color = _black,
    pw.TextAlign align = pw.TextAlign.right}) {
  return pw.Text(s,
      textDirection: pw.TextDirection.rtl,
      textAlign: align,
      style: pw.TextStyle(
          font: bold ? _bold : _regular, fontSize: size, color: color));
}

String _m(dynamic v) => money(v);
String _pct(dynamic v) {
  final d = toD(v);
  return '${d.toStringAsFixed(d % 1 == 0 ? 0 : 1)}%';
}

Future<Uint8List> buildInvoicePdf(String invoiceId) async {
  await _loadAssets();
  final inv = (await db.collection('invoices').doc(invoiceId).get()).data();
  if (inv == null) throw 'الفاتورة مش موجودة';
  final customerId = (inv['customerId'] ?? '').toString();
  final user = (await db.collection('users').doc(customerId).get()).data() ?? {};
  final pays = (await db
          .collection('payments')
          .where('customerId', isEqualTo: customerId)
          .where('invoiceId', isEqualTo: invoiceId)
          .get())
      .docs
      .map((e) => e.data())
      .toList()
    ..sort((a, b) => (tsToDate(a['createdAt']) ?? DateTime(2100))
        .compareTo(tsToDate(b['createdAt']) ?? DateTime(2100)));

  final items = List<Map<String, dynamic>>.from(
      (inv['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
  final hasReturns = items.any((e) => toI(e['returnedQty']) > 0);
  final bal = toD(inv['balance']);
  final created = tsToDate(inv['createdAt']) ?? DateTime.now();
  final due = tsToDate(inv['dueDate']);
  var days = toI(inv['collectionDays']);
  if (days == 0 && due != null) {
    days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(created.year, created.month, created.day))
        .inDays;
  }
  final totalQty = items.fold(0, (a, e) => a + toI(e['qty']));

  final doc = pw.Document(
    title: 'SOL Invoice ${inv['number']}',
    author: 'SOL Perfume',
    theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
  );

  // -------- الجدول (الأعمدة متكتبة من الشمال لليمين عشان تظهر صح RTL) --------
  final headers = <String>[
    'الإجمالي',
    if (hasReturns) 'مرتجع',
    'سعر الجملة',
    'الخصم',
    'سعر البيع',
    'الكمية',
    'الصنف',
    'م',
  ];
  final widths = <double>[
    1.3,
    if (hasReturns) 0.8,
    1.2,
    0.8,
    1.1,
    0.8,
    3.2,
    0.5,
  ];

  pw.Widget cell(String s,
          {bool bold = false,
          PdfColor color = _black,
          pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: _t(s, size: 9.5, bold: bold, color: color, align: align),
      );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: _black),
      children: [for (final h in headers) cell(h, bold: true, color: _gold)],
    ),
  ];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final q = toI(it['qty']);
    final r = toI(it['returnedQty']);
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: i.isOdd ? _goldLight : PdfColors.white),
      children: [
        cell(_m(toD(it['unitNet']) * q), bold: true),
        if (hasReturns) cell(r > 0 ? '$r' : '-', color: r > 0 ? _red : _grey),
        cell(_m(it['unitNet'])),
        cell(_pct(it['discount'])),
        cell(_m(it['sellPrice'])),
        cell('$q', bold: true),
        cell((it['name'] ?? '').toString(), align: pw.TextAlign.right),
        cell('${i + 1}', color: _grey),
      ],
    ));
  }

  pw.Widget infoRow(String k, String v, {bool bold = false, PdfColor color = _black}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(children: [
          pw.Expanded(child: _t(v, bold: bold, color: color, align: pw.TextAlign.left)),
          pw.SizedBox(width: 8),
          _t(k, color: _grey),
        ]),
      );

  pw.Widget box(String title, List<pw.Widget> children) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _t(title, bold: true, size: 11, color: _gold),
          pw.Divider(color: _line, height: 8),
          ...children,
        ]),
      );

  final totals = <pw.Widget>[
    infoRow('إجمالي سعر البيع', _m(inv['sellTotal'])),
    infoRow('إجمالي الخصم', '- ${_m(inv['discountTotal'])}', color: _green),
    infoRow('إجمالي سعر الجملة', _m(inv['gross'] ?? inv['wholesaleTotal'])),
    if (toI(inv['pointsRedeemed']) > 0)
      infoRow('خصم نقاط (${inv['pointsRedeemed']} نقطة)', '- ${_m(inv['redeemValue'])}',
          color: _green),
    pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: _black,
      child: pw.Row(children: [
        pw.Expanded(
            child: _t(_m(inv['total']),
                bold: true, size: 13, color: _gold, align: pw.TextAlign.left)),
        _t('صافي الفاتورة', bold: true, size: 12, color: PdfColors.white),
      ]),
    ),
    infoRow('المدفوع', _m(inv['paid']), color: _green),
    if (toD(inv['returned']) > 0) infoRow('المرتجعات', '- ${_m(inv['returned'])}', color: _red),
    pw.Divider(color: _line, height: 6),
    infoRow(bal < -0.009 ? 'رصيد لصالح العميل' : 'المتبقي على العميل', _m(bal.abs()),
        bold: true, color: bal > 0.009 ? _red : _green),
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: pw.TextDirection.ltr,
    margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
    header: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(color: _black, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Container(
          width: 70,
          height: 70,
          child: pw.Image(_logo!, fit: pw.BoxFit.cover),
        ),
        pw.SizedBox(width: 12),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('SOL PERFUME',
              style: pw.TextStyle(
                  font: _bold, fontSize: 18, color: _gold, letterSpacing: 2)),
          _t('عطرك، بصمتك', color: PdfColors.white, size: 10),
        ]),
        pw.Spacer(),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _t('فاتورة بيع', bold: true, size: 20, color: _gold),
          _t('رقم ${inv['number']}', color: PdfColors.white, size: 12),
          if (ctx.pagesCount > 1)
            _t('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
                color: PdfColors.grey400, size: 8),
        ]),
      ]),
    ),
    footer: (ctx) => pw.Column(children: [
      pw.Divider(color: _gold, thickness: 1),
      pw.Row(children: [
        _t('صفحة ${ctx.pageNumber} / ${ctx.pagesCount}', size: 8, color: _grey),
        pw.Spacer(),
        _t('شكراً لتعاملكم مع SOL  -  عطرك، بصمتك', size: 9, color: _grey),
      ]),
    ]),
    build: (ctx) => [
      // بيانات العميل + الفاتورة
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: box('بيانات الفاتورة', [
            infoRow('رقم الفاتورة', '${inv['number']}', bold: true),
            infoRow('التاريخ', fmtDate(inv['createdAt'], time: true)),
            infoRow('مدة التحصيل', '$days يوم'),
            infoRow('تاريخ الاستحقاق', fmtDate(inv['dueDate']), bold: true, color: _red),
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: box('بيانات العميل', [
            infoRow('المحل', (user['shopName'] ?? inv['customerName'] ?? '').toString(),
                bold: true),
            if ((user['ownerName'] ?? '').toString().isNotEmpty)
              infoRow('صاحب المحل', user['ownerName']),
            if ((user['phone'] ?? '').toString().isNotEmpty) infoRow('الموبايل', user['phone']),
            if ((user['address'] ?? '').toString().isNotEmpty)
              infoRow('العنوان', user['address']),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: {
          for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]),
        },
        children: rows,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Row(children: [
          pw.Spacer(),
          _t('عدد الأصناف: ${items.length}   -   إجمالي القطع: $totalQty',
              size: 9, color: _grey),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            if (pays.isNotEmpty)
              box('الدفعات', [
                for (final p in pays)
                  infoRow(fmtDate(p['createdAt']), _m(p['amount']), color: _green),
              ]),
            if (pays.isNotEmpty) pw.SizedBox(height: 8),
            if (toI(inv['pointsEarned']) > 0)
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                    color: _goldLight, borderRadius: pw.BorderRadius.circular(6)),
                child: _t('كسبت ${inv['pointsEarned']} نقطة مع الفاتورة دي',
                    bold: true, align: pw.TextAlign.center),
              ),
            if ((inv['note'] ?? '').toString().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              box('ملاحظات', [_t(inv['note'].toString())]),
            ],
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(flex: 6, child: box('الحساب', totals)),
      ]),
      pw.SizedBox(height: 40),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Column(children: [
            pw.Divider(color: _black, thickness: 0.6),
            _t('توقيع المستلم', color: _grey, align: pw.TextAlign.center),
          ]),
        ),
        pw.SizedBox(width: 60),
        pw.Expanded(
          child: pw.Column(children: [
            pw.Divider(color: _black, thickness: 0.6),
            _t('عن SOL', color: _grey, align: pw.TextAlign.center),
          ]),
        ),
      ]),
    ],
  ));
  return doc.save();
}

Future<void> shareInvoicePdf(BuildContext context, String invoiceId) async {
  try {
    toast(context, 'بيتعمل ملف الفاتورة...');
    final bytes = await buildInvoicePdf(invoiceId);
    final n = (await db.collection('invoices').doc(invoiceId).get()).data()?['number'];
    await Printing.sharePdf(bytes: bytes, filename: 'SOL-invoice-$n.pdf');
  } catch (e) {
    if (context.mounted) toast(context, 'مقدرناش نعمل الملف: $e', error: true);
  }
}

Future<void> printInvoicePdf(BuildContext context, String invoiceId) async {
  try {
    await Printing.layoutPdf(
        name: 'SOL-invoice', onLayout: (_) => buildInvoicePdf(invoiceId));
  } catch (e) {
    if (context.mounted) toast(context, 'مقدرناش نطبع: $e', error: true);
  }
}
