import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final days = TextEditingController();
  final perPoint = TextEditingController();
  final forReward = TextEditingController();
  final reward = TextEditingController();
  bool loaded = false, busy = false;

  @override
  void initState() {
    super.initState();
    getSettings().then((s) {
      if (!mounted) return;
      setState(() {
        days.text = '${s.collectionDays}';
        perPoint.text = _n(s.amountPerPoint);
        forReward.text = '${s.pointsForReward}';
        reward.text = _n(s.rewardValue);
        loaded = true;
      });
    });
  }

  String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  AppSettings get current => AppSettings(
        collectionDays: toI(days.text),
        amountPerPoint: toD(perPoint.text),
        pointsForReward: toI(forReward.text),
        rewardValue: toD(reward.text),
      );

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await settingsRef.set(current.toMap(), SetOptions(merge: true));
      if (mounted) toast(context, 'اتحفظت الإعدادات ✔');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _f(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, helperText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: !loaded
          ? const Loading()
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text('⏰ التحصيل',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kPrimary)),
              const SizedBox(height: 10),
              _f(days, 'عدد أيام التحصيل',
                  'الفاتورة تستحق بعد كام يوم — بعدها يظهر لك تنبيه إن العميل متأخر'),
              const Divider(height: 30),
              const Text('⭐ نظام النقاط',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kPrimary)),
              const SizedBox(height: 10),
              _f(perPoint, 'كل كام جنيه = نقطة', 'مثلاً 10 يعني فاتورة 1000 جنيه = 100 نقطة'),
              _f(forReward, 'كل كام نقطة', 'عدد النقاط اللي العميل يستبدلها'),
              _f(reward, '= كام جنيه خصم', 'قيمة الخصم مقابل النقاط'),
              Card(
                color: const Color(0xFFFFF6E6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                      'العميل هيشوف: ${current.rulesText}\nيعني فاتورة 1000 جنيه = ${current.pointsFor(1000)} نقطة',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                    onPressed: busy ? null : save, child: const Text('حفظ')),
              ),
            ]),
    );
  }
}
