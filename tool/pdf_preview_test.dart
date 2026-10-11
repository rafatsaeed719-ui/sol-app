// بيولّد فاتورة تجريبية PDF عشان نشوف شكلها (بيشتغل في البناء بس)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:store/shared/invoice_pdf.dart';

void main() {
  test('sample invoice pdf', () async {
    pw.Font f(String p) => pw.Font.ttf(File(p).readAsBytesSync().buffer.asByteData());
    setPdfAssets(f('assets/fonts/Amiri-Regular.ttf'), f('assets/fonts/Amiri-Bold.ttf'),
        pw.MemoryImage(File('assets/logo.png').readAsBytesSync()));
    final now = DateTime(2026, 10, 11, 14, 30);
    final inv = <String, dynamic>{
      'number': 27,
      'customerName': 'عطور الأمل',
      'items': [
        {'name': 'SOL Oud Royal 100ml', 'qty': 12, 'returnedQty': 2, 'sellPrice': 450, 'discount': 30, 'unitNet': 315},
        {'name': 'عطر مسك الليل 50 مل', 'qty': 24, 'returnedQty': 0, 'sellPrice': 250, 'discount': 25, 'unitNet': 187.5},
        {'name': 'بخاخ جسم ورد طائفي', 'qty': 6, 'returnedQty': 0, 'sellPrice': 120, 'discount': 20, 'unitNet': 96},
      ],
      'sellTotal': 12120, 'discountTotal': 3300, 'gross': 8820, 'wholesaleTotal': 8820,
      'pointsRedeemed': 100, 'redeemValue': 50, 'total': 8770, 'paid': 3000,
      'returned': 630, 'balance': 5140, 'pointsEarned': 877, 'note': 'التسليم يوم الخميس',
      'collectionDays': 15, 'createdAt': now, 'dueDate': now.add(const Duration(days: 15)),
    };
    final user = <String, dynamic>{
      'shopName': 'عطور الأمل', 'ownerName': 'محمد أحمد', 'phone': '01012345678',
      'address': 'شارع الجمهورية - أسيوط',
    };
    final pays = [<String, dynamic>{'amount': 3000, 'createdAt': now}];
    final bytes = await renderInvoicePdf(inv, user, pays);
    File('SOL-invoice-sample.pdf').writeAsBytesSync(bytes);
  });
}
