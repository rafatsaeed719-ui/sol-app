import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../core/app.dart';
import 'customer_accounts.dart';

/// لوحة المدير العام: المحلات المشتركة في البرنامج
class StoresAdmin extends StatelessWidget {
  const StoresAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المحلات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreForm())),
        icon: const Icon(Icons.add_business),
        label: const Text('محل جديد'),
      ),
      body: StreamBuilder(
        stream: db.collection('stores').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final docs = [...snap.data!.docs]..sort((a, b) {
              if (a.id == kMainStore) return -1;
              if (b.id == kMainStore) return 1;
              return (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString());
            });
          final active = docs.where((d) => !storeBlocked(d.data())).length;
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(child: StatTile('المحلات', '${docs.length}', icon: Icons.store)),
                Expanded(
                    child: StatTile('شغالة', '$active',
                        icon: Icons.check_circle, color: kSuccess)),
                Expanded(
                    child: StatTile('متوقفة', '${docs.length - active}',
                        icon: Icons.block, color: kDanger)),
              ]),
            ),
            Card(
              color: const Color(0xFFFFF6E6),
              child: ListTile(
                leading: const Icon(Icons.visibility, color: kAccent),
                title: Text('إنت دلوقتي داخل على: $storeName'),
                subtitle: const Text('دوس "ادخل" على أي محل عشان تشوفه وتديره زي صاحبه'),
              ),
            ),
            for (final d in docs) _StoreCard(id: d.id, s: d.data()),
          ]);
        },
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> s;
  const _StoreCard({required this.id, required this.s});

  @override
  Widget build(BuildContext context) {
    final blocked = storeBlocked(s);
    final end = tsToDate(s['subscriptionEnd']);
    final current = id == sid;
    return Card(
      shape: current
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kAccent, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            StoreLogo(size: 52, store: s, storeId: id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((s['name'] ?? id).toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('الكود: $id', style: const TextStyle(color: Colors.black54)),
                if ((s['ownerUsername'] ?? '').toString().isNotEmpty)
                  Text('صاحب المحل: ${s['ownerUsername']}',
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: (blocked ? kDanger : kSuccess).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(blocked ? 'متوقف' : 'شغال',
                  style: TextStyle(
                      color: blocked ? kDanger : kSuccess, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (id != kMainStore)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  end == null
                      ? 'الاشتراك: مفتوح'
                      : 'الاشتراك لحد: ${fmtDate(end)}${end.isBefore(DateTime.now()) ? ' (خلص)' : ' (فاضل ${end.difference(DateTime.now()).inDays} يوم)'}',
                  style: TextStyle(
                      color: end != null && end.isBefore(DateTime.now()) ? kDanger : null)),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            FilledButton.tonalIcon(
              onPressed: current
                  ? null
                  : () {
                      Session.superStore.value = id;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
              icon: const Icon(Icons.login),
              label: Text(current ? 'إنت جوّاه' : 'ادخل'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => StoreForm(id: id, data: s))),
              icon: const Icon(Icons.edit),
              label: const Text('تعديل'),
            ),
            if (id != kMainStore)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: s['active'] == true ? kDanger : kSuccess),
                onPressed: () async {
                  final on = s['active'] == true;
                  if (!await confirm(context, on ? 'إيقاف المحل' : 'تشغيل المحل',
                      on ? 'المحل وعملاؤه مش هيقدروا يدخلوا. متأكد؟' : 'هيرجع يشتغل عادي.')) {
                    return;
                  }
                  await db.collection('stores').doc(id).update({'active': !on});
                },
                icon: Icon(s['active'] == true ? Icons.block : Icons.play_arrow),
                label: Text(s['active'] == true ? 'إيقاف' : 'تشغيل'),
              ),
            if (id != kMainStore)
              OutlinedButton.icon(
                onPressed: () async {
                  final base = (end != null && end.isAfter(DateTime.now())) ? end : DateTime.now();
                  final months = await showDialog<int>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('تجديد الاشتراك'),
                      children: [
                        for (final m in const [1, 3, 6, 12])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(c, m),
                            child: Text(m == 12 ? 'سنة' : '$m شهر',
                                style: const TextStyle(fontSize: 16)),
                          ),
                      ],
                    ),
                  );
                  if (months == null) return;
                  final ne = DateTime(base.year, base.month + months, base.day);
                  await db.collection('stores').doc(id).update(
                      {'subscriptionEnd': Timestamp.fromDate(ne), 'active': true});
                  if (context.mounted) toast(context, 'اتجدد لحد ${fmtDate(ne)}');
                },
                icon: const Icon(Icons.autorenew),
                label: const Text('تجديد'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// إضافة / تعديل محل
class StoreForm extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  const StoreForm({super.key, this.id, this.data});
  @override
  State<StoreForm> createState() => _StoreFormState();
}

class _StoreFormState extends State<StoreForm> {
  final code = TextEditingController();
  final name = TextEditingController();
  final slogan = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final ownerName = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController(text: randomPassword());
  String? logo;
  DateTime? end = DateTime.now().add(const Duration(days: 30));
  bool busy = false;

  bool get edit => widget.id != null;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      code.text = widget.id!;
      name.text = d['name'] ?? '';
      slogan.text = d['slogan'] ?? '';
      phone.text = d['phone'] ?? '';
      address.text = d['address'] ?? '';
      logo = d['logo'];
      end = tsToDate(d['subscriptionEnd']);
    }
  }

  Future<void> save() async {
    final id = code.text.trim().toLowerCase();
    if (name.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المحل', error: true);
      return;
    }
    if (!edit) {
      if (!RegExp(r'^[a-z0-9_-]{2,20}$').hasMatch(id)) {
        toast(context, 'كود المحل بالإنجليزي الصغير أو أرقام من غير مسافات (زي ahmed1)',
            error: true);
        return;
      }
      if (!validUsername(username.text) || password.text.length < 6) {
        toast(context, 'اسم مستخدم صاحب المحل (إنجليزي) وكلمة سر 6 على الأقل', error: true);
        return;
      }
    }
    setState(() => busy = true);
    try {
      final ref = db.collection('stores').doc(id);
      final data = {
        'name': name.text.trim(),
        'slogan': slogan.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'logo': logo ?? '',
        'subscriptionEnd': end == null ? null : Timestamp.fromDate(end!),
      };
      if (edit) {
        await ref.update(data);
        if (mounted) Navigator.pop(context);
      } else {
        if ((await ref.get()).exists) throw 'الكود ده متاخد — اختار كود تاني';
        await ref.set({
          ...data,
          'active': true,
          'ownerUsername': username.text.trim().toLowerCase(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        final ownerUid = await createCustomerAccount(
          username: username.text,
          password: password.text,
          profile: {
            'storeId': id,
            'role': 'owner',
            'shopName': name.text.trim(),
            'ownerName': ownerName.text.trim(),
            'phone': phone.text.trim(),
            'address': address.text.trim(),
            'photo': logo ?? '',
          },
        );
        await ref.update({'ownerUid': ownerUid});
        if (!mounted) return;
        await showCredentials(context,
            shop: name.text.trim(),
            username: username.text.trim().toLowerCase(),
            password: password.text,
            phone: phone.text.trim());
        if (mounted) Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        toast(context,
            e.code == 'email-already-in-use' ? 'اسم المستخدم ده متاخد' : authError(e),
            error: true);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(edit ? 'تعديل محل' : 'محل جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final p = await pickImageB64(context, maxWidth: 500);
              if (p != null) setState(() => logo = p);
            },
            child: Column(children: [
              StoreLogo(
                  size: 100,
                  store: {'logo': logo, 'name': name.text},
                  storeId: code.text.isEmpty ? '?' : code.text),
              const SizedBox(height: 6),
              const Text('دوس لاختيار لوجو المحل', style: TextStyle(color: Colors.black54)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _f(name, 'اسم المحل *', Icons.store, onChanged: (_) => setState(() {})),
        _f(code, 'كود المحل * (إنجليزي — العملاء بيكتبوه وهم بيسجلوا)', Icons.qr_code,
            ltr: true, enabled: !edit),
        _f(slogan, 'جملة تحت الاسم (اختياري)', Icons.short_text),
        _f(phone, 'موبايل المحل', Icons.phone, ltr: true),
        _f(address, 'العنوان', Icons.home_outlined),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_available),
            title: Text(end == null ? 'الاشتراك مفتوح (من غير تاريخ)' : 'الاشتراك لحد ${fmtDate(end)}'),
            subtitle: const Text('دوس لتغيير التاريخ'),
            trailing: end == null
                ? null
                : IconButton(
                    tooltip: 'من غير تاريخ',
                    onPressed: () => setState(() => end = null),
                    icon: const Icon(Icons.all_inclusive)),
            onTap: () async {
              final p = await showDatePicker(
                  context: context,
                  initialDate: end ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2040));
              if (p != null) setState(() => end = p);
            },
          ),
        ),
        if (!edit) ...[
          const Divider(height: 28),
          const Text('🔐 حساب صاحب المحل',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          _f(ownerName, 'اسم صاحب المحل', Icons.person_outline),
          _f(username, 'اسم المستخدم * (إنجليزي)', Icons.badge_outlined, ltr: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: password,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'كلمة السر *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => password.text = randomPassword()),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : save,
            child: busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(edit ? 'حفظ' : 'إنشاء المحل وحساب صاحبه'),
          ),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {bool ltr = false, bool enabled = true, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: enabled,
          onChanged: onChanged,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}
