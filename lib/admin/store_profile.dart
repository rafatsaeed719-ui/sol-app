import 'package:flutter/material.dart';

import '../core/app.dart';

/// صاحب المحل يعدّل اسم ولوجو محله ورسالة الترحيب لعملائه
class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});
  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final name = TextEditingController();
  final slogan = TextEditingController();
  final welcome = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  String? logo;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final s = Session.store;
    name.text = (s['name'] ?? '').toString();
    slogan.text = (s['slogan'] ?? '').toString();
    welcome.text = (s['welcome'] ?? '').toString();
    phone.text = (s['phone'] ?? '').toString();
    address.text = (s['address'] ?? '').toString();
    logo = (s['logo'] ?? '').toString();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المحل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await db.collection('stores').doc(sid).update({
        'name': name.text.trim(),
        'slogan': slogan.text.trim(),
        'welcome': welcome.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'logo': logo ?? '',
      });
      if (mounted) {
        toast(context, 'اتحفظت بيانات المحل ✔');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final end = tsToDate(Session.store['subscriptionEnd']);
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات المحل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final p = await pickImageB64(context, maxWidth: 500);
              if (p != null) setState(() => logo = p);
            },
            child: Column(children: [
              StoreLogo(size: 110, store: {'logo': logo, 'name': name.text}),
              const SizedBox(height: 6),
              const Text('دوس لتغيير اللوجو', style: TextStyle(color: Colors.black54)),
              if ((logo ?? '').isNotEmpty)
                TextButton(
                    onPressed: () => setState(() => logo = ''),
                    child: Text(sid == kMainStore ? 'رجّع لوجو SOL الأصلي' : 'شيل اللوجو')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.qr_code),
            title: Text('كود المحل: $sid', textDirection: TextDirection.ltr),
            subtitle: const Text('العملاء بيكتبوه لو سجلوا بنفسهم'),
          ),
        ),
        if (sid != kMainStore)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available),
              title: Text(end == null ? 'الاشتراك مفتوح' : 'الاشتراك لحد ${fmtDate(end)}'),
            ),
          ),
        const SizedBox(height: 8),
        _f(name, 'اسم المحل *', Icons.store, onChanged: (_) => setState(() {})),
        _f(slogan, 'جملة تحت الاسم (بتظهر في الفاتورة)', Icons.short_text),
        _f(phone, 'موبايل المحل', Icons.phone, ltr: true),
        _f(address, 'العنوان', Icons.home_outlined),
        _f(welcome, 'رسالة الترحيب للعملاء الجداد', Icons.waving_hand, lines: 4),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton(onPressed: busy ? null : save, child: const Text('حفظ')),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {bool ltr = false, int lines = 1, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          onChanged: onChanged,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}
