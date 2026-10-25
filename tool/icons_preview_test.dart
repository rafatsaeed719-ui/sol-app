// بيرسم صورة للأيقونات المجسمة عشان نشوف شكلها (بيشتغل في البناء بس)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/core/fx.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  testWidgets('3d icons preview', (tester) async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    await _font('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await _font('Amiri', 'assets/fonts/Amiri-Bold.ttf');
    tester.view.physicalSize = const Size(900, 520);
    tester.view.devicePixelRatio = 1.5;
    const items = [
      [Icons.dashboard, tGold, 'الرئيسية'],
      [Icons.shopping_cart, tBlue, 'الطلبات'],
      [Icons.warehouse, tGreen, 'المخزن'],
      [Icons.account_balance_wallet, tPurple, 'المصروفات'],
      [Icons.insights, tOrange, 'الرسومات'],
      [Icons.location_history, tTeal, 'الزيارات'],
      [Icons.campaign, tRed, 'واتساب'],
      [Icons.storefront, tBlack, 'المحل'],
    ];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Amiri'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(spacing: 22, runSpacing: 22, children: [
              for (final it in items)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon3D(it[0] as IconData, size: 64, tone: it[1] as Tone),
                  const SizedBox(height: 8),
                  Text(it[2] as String, style: const TextStyle(fontSize: 16)),
                ]),
              Container(
                color: const Color(0xFF141414),
                padding: const EdgeInsets.all(16),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon3D(Icons.auto_awesome, size: 48, tone: tGold),
                  SizedBox(width: 12),
                  Icon3D(Icons.home, size: 34, tone: tGold, circle: true),
                  SizedBox(width: 12),
                  Icon3D(Icons.done_all, size: 48, tone: tGreen, circle: true),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(Scaffold), matchesGoldenFile('icons_preview.png'));
  });
}
