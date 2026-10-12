import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../core/app.dart';
import '../core/data.dart';
import '../core/platform.dart';
import 'customer_accounts.dart';

/// لوحة المدير العام: المحلات، المستخدمين، الباقات، الاشتراكات
class StoresAdmin extends StatelessWidget {
  const StoresAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة البرنامج'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: kAccent,
            unselectedLabelColor: Colors.white70,
            indicatorColor: kAccent,
            tabs: [
              Tab(text: 'المحلات'),
              Tab(text: 'المستخدمين'),
              Tab(text: 'الباقات والأسعار'),
              Tab(text: 'الاشتراكات'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _StoresTab(),
          AllUsersTab(),
          PlansTab(),
          SubscriptionsTab(),
        ]),
      ),
    );
  }
}

class _StoresTab extends StatelessWidget {
  const _StoresTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addStore',
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
          final pending = docs.where((d) => d.data()['status'] == 'pending').toList();
          final rest = docs.where((d) => d.data()['status'] != 'pending').toList();
          final active = rest.where((d) => !storeBlocked(d.data())).length;
          final soon = rest.where((d) {
            final e = tsToDate(d.data()['subscriptionEnd']);
            return d.id != kMainStore &&
                e != null &&
                e.isAfter(DateTime.now()) &&
                e.difference(DateTime.now()).inDays <= 7;
          }).length;
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.1,
                children: [
                  StatTile('المحلات', '${rest.length}', icon: Icons.store),
                  StatTile('شغالة', '$active', icon: Icons.check_circle, color: kSuccess),
                  StatTile('طلبات اشتراك جديدة', '${pending.length}',
                      icon: Icons.hourglass_top, color: pending.isEmpty ? kPrimary : kAccent),
                  StatTile('بتخلص خلال أسبوع', '$soon',
                      icon: Icons.timer, color: soon == 0 ? kPrimary : kDanger),
                ],
              ),
            ),
            Card(
              color: const Color(0xFFFFF6E6),
              child: ListTile(
                leading: const Icon(Icons.visibility, color: kAccent),
                title: Text('إنت دلوقتي داخل على: $storeName'),
                subtitle: const Text('دوس "ادخل" على أي محل عشان تديره زي صاحبه'),
              ),
            ),
            if (pending.isNotEmpty) ...[
              SectionTitle('🆕 طلبات اشتراك مستنية التفعيل (${pending.length})'),
              for (final d in pending) _StoreCard(id: d.id, s: d.data()),
            ],
            const SectionTitle('المحلات'),
            for (final d in rest) _StoreCard(id: d.id, s: d.data()),
          ]);
        },
      ),
    );
  }
}

/// اختيار باقة للتفعيل أو التجديد
Future<void> pickPlanAndActivate(
    BuildContext context, String id, Map<String, dynamic> s) async {
  final cfg = PlatformConfig.fromMap((await platformRef.get()).data());
  if (!context.mounted) return;
  final requested = s['requestedPlan'] is Map ? Plan.fromMap(s['requestedPlan']) : null;
  final plan = await showDialog<Plan>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(s['status'] == 'pending' ? 'تفعيل الاشتراك' : 'تجديد الاشتراك'),
      children: [
        for (final p in cfg.plans)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, p),
            child: Row(children: [
              Expanded(
                child: Text('${p.name} (${p.period})${requested?.name == p.name ? '  ← اللي اختاره' : ''}',
                    style: const TextStyle(fontSize: 16)),
              ),
              Text(money(p.price), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
      ],
    ),
  );
  if (plan == null || !context.mounted) return;
  final paid = TextEditingController(
      text: plan.price % 1 == 0 ? plan.price.toStringAsFixed(0) : plan.price.toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${plan.name} — ${plan.period}'),
      content: TextField(
        controller: paid,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'المبلغ اللي اتدفع'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تفعيل')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final end = await activateStore(id, s, plan, paid: toD(paid.text));
    if (context.mounted) toast(context, 'اتفعل الاشتراك لحد ${fmtDate(end)} ✔');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

class _StoreCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> s;
  const _StoreCard({required this.id, required this.s});

  @override
  Widget build(BuildContext context) {
    final pending = s['status'] == 'pending';
    final rejected = s['status'] == 'rejected';
    final blocked = storeBlocked(s);
    final end = tsToDate(s['subscriptionEnd']);
    final current = id == sid;
    final plan = s['plan'] is Map ? Plan.fromMap(s['plan']) : null;
    final req = s['requestedPlan'] is Map ? Plan.fromMap(s['requestedPlan']) : null;
    final label = pending
        ? 'مستني التفعيل'
        : rejected
            ? 'مرفوض'
            : blocked
                ? 'متوقف'
                : 'شغال';
    final color = pending ? kAccent : (blocked ? kDanger : kSuccess);
    return Card(
      color: pending ? const Color(0xFFFFF8EC) : null,
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
                  Text('صاحب المحل: ${s['ownerUsername']}${(s['phone'] ?? '').toString().isEmpty ? '' : ' • ${s['phone']}'}',
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (pending && req != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('طالب باقة: ${req.name} (${req.period}) — ${money(req.price)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (id != kMainStore && !pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${plan == null ? '' : 'الباقة: ${plan.name} • '}${end == null ? 'الاشتراك: مفتوح' : 'لحد ${fmtDate(end)}${end.isBefore(DateTime.now()) ? ' (خلص)' : ' (فاضل ${end.difference(DateTime.now()).inDays} يوم)'}'}',
                  style: TextStyle(
                      color: end != null && end.isBefore(DateTime.now()) ? kDanger : null)),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (pending) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kSuccess),
                onPressed: () => pickPlanAndActivate(context, id, s),
                icon: const Icon(Icons.check),
                label: const Text('تفعيل'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: kDanger),
                onPressed: () async {
                  if (!await confirm(context, 'رفض الطلب', 'متأكد إنك عاوز ترفض طلب ${s['name']}؟')) {
                    return;
                  }
                  await db.collection('stores').doc(id).update({'status': 'rejected', 'active': false});
                },
                icon: const Icon(Icons.close),
                label: const Text('رفض'),
              ),
            ],
            if (!pending)
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
            if (id != kMainStore && !pending)
              OutlinedButton.icon(
                onPressed: () => pickPlanAndActivate(context, id, s),
                icon: const Icon(Icons.autorenew),
                label: const Text('تجديد'),
              ),
            if (id != kMainStore && !pending)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: s['active'] == true ? kDanger : kSuccess),
                onPressed: () async {
                  final on = s['active'] == true;
                  if (!await confirm(context, on ? 'إيقاف المحل' : 'تشغيل المحل',
                      on ? 'المحل وعملاؤه مش هيقدروا يدخلوا. متأكد؟' : 'هيرجع يشتغل عادي.')) {
                    return;
                  }
                  await db
                      .collection('stores')
                      .doc(id)
                      .update({'active': !on, if (!on) 'status': 'active'});
                },
                icon: Icon(s['active'] == true ? Icons.block : Icons.play_arrow),
                label: Text(s['active'] == true ? 'إيقاف' : 'تشغيل'),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ======================== كل المستخدمين ========================

class AllUsersTab extends StatefulWidget {
  const AllUsersTab({super.key});
  @override
  State<AllUsersTab> createState() => _AllUsersTabState();
}

class _AllUsersTabState extends State<AllUsersTab> {
  String q = '';
  String role = '';
  String store = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('stores').snapshots(),
      builder: (context, ss) {
        final stores = {
          for (final d in ss.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            d.id: (d.data()['name'] ?? d.id).toString()
        };
        return StreamBuilder(
          stream: db.collection('users').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return EmptyView('${snap.error}');
            if (!snap.hasData) return const Loading();
            final all = snap.data!.docs;
            final list = all.where((d) {
              final m = d.data();
              final st = (m['storeId'] ?? kMainStore).toString();
              final r = (m['role'] ?? 'customer').toString();
              if (role.isNotEmpty && r != role) return false;
              if (store.isNotEmpty && st != store) return false;
              if (q.isNotEmpty &&
                  !'${m['shopName']} ${m['ownerName']} ${m['phone']} ${m['username']} ${m['email']}'
                      .toLowerCase()
                      .contains(q.toLowerCase())) {
                return false;
              }
              return true;
            }).toList()
              ..sort((a, b) => (a.data()['shopName'] ?? '')
                  .toString()
                  .compareTo((b.data()['shopName'] ?? '').toString()));
            final owners = all.where((d) => d.data()['role'] == 'owner').length;
            final disabled = all.where((d) => d.data()['disabled'] == true).length;
            return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: StatTile('الكل', '${all.length}', icon: Icons.people)),
                  Expanded(child: StatTile('أصحاب محلات', '$owners', icon: Icons.store)),
                  Expanded(
                      child: StatTile('موقوفين', '$disabled',
                          icon: Icons.block, color: disabled > 0 ? kDanger : kPrimary)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'دوّر بالاسم أو الموبايل أو اسم المستخدم',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => q = v.trim()),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final r in const [
                      ['', 'الكل'],
                      ['owner', 'أصحاب المحلات'],
                      ['customer', 'العملاء'],
                    ])
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                            label: Text(r[1]),
                            selected: role == r[0],
                            onSelected: (_) => setState(() => role = r[0])),
                      ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: DropdownButton<String>(
                        value: store,
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('كل المحلات')),
                          for (final e in stores.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => store = v ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
              if (list.isEmpty) const EmptyView('مفيش حد'),
              for (final d in list)
                Card(
                  color: d.data()['disabled'] == true ? const Color(0xFFFDECEA) : null,
                  child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => UserEditScreen(userId: d.id, stores: stores))),
                    leading: Avatar(d.data()['photo']),
                    title: Text(
                        (d.data()['shopName'] ?? d.data()['ownerName'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      d.data()['role'] == 'owner' ? '👑 صاحب محل' : 'عميل',
                      stores[(d.data()['storeId'] ?? kMainStore).toString()] ??
                          (d.data()['storeId'] ?? kMainStore).toString(),
                      (d.data()['username'] ?? d.data()['email'] ?? '').toString(),
                    ].join(' • ')),
                    trailing: d.data()['disabled'] == true
                        ? const Text('موقوف',
                            style: TextStyle(color: kDanger, fontWeight: FontWeight.bold))
                        : const Icon(Icons.chevron_left),
                  ),
                ),
            ]);
          },
        );
      },
    );
  }
}

/// تعديل أي مستخدم: البيانات، الإيقاف، كلمة السر
class UserEditScreen extends StatefulWidget {
  final String userId;
  final Map<String, String> stores;
  const UserEditScreen({super.key, required this.userId, required this.stores});
  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final shop = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  bool loaded = false, busy = false;
  Map<String, dynamic> m = {};

  @override
  void initState() {
    super.initState();
    db.collection('users').doc(widget.userId).get().then((s) {
      if (!mounted) return;
      setState(() {
        m = s.data() ?? {};
        shop.text = (m['shopName'] ?? '').toString();
        owner.text = (m['ownerName'] ?? '').toString();
        phone.text = (m['phone'] ?? '').toString();
        address.text = (m['address'] ?? '').toString();
        loaded = true;
      });
    });
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await db.collection('users').doc(widget.userId).update({
        'shopName': shop.text.trim(),
        'ownerName': owner.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
      });
      if (mounted) {
        toast(context, 'اتحفظ ✔');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> changePass() async {
    final email = loginEmailOf(m);
    final old = (m['password'] ?? '').toString();
    if (old.isEmpty) {
      final real = email.isNotEmpty && !email.endsWith('@$kUserDomain');
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('كلمة السر مش متسجلة'),
          content: Text(real
              ? 'الحساب ده اتعمل قبل ما نسجل كلمات السر. نقدر نبعتله رسالة على إيميله ($email) يغيّر منها كلمة السر.'
              : 'الحساب ده اتعمل قبل ما نسجل كلمات السر، ومينفعش تتغير من هنا. الأسهل تعمله حساب جديد.'),
          actions: [
            if (real)
              FilledButton(
                onPressed: () async {
                  await auth.sendPasswordResetEmail(email: email);
                  if (c.mounted) Navigator.pop(c);
                  if (mounted) toast(context, 'اتبعتت رسالة تغيير كلمة السر');
                },
                child: const Text('ابعت الرسالة'),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('تمام')),
          ],
        ),
      );
      return;
    }
    final c = TextEditingController(text: randomPassword());
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('كلمة سر جديدة'),
        content: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'كلمة السر الجديدة (6 على الأقل)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تغيير')),
        ],
      ),
    );
    if (ok != true) return;
    if (c.text.length < 6) {
      if (mounted) toast(context, 'كلمة السر 6 على الأقل', error: true);
      return;
    }
    try {
      await changeUserPassword(widget.userId, email, old, c.text);
      setState(() => m['password'] = c.text);
      if (mounted) {
        await showCredentials(context,
            shop: (m['shopName'] ?? '').toString(),
            username: (m['username'] ?? email).toString(),
            password: c.text,
            phone: (m['phone'] ?? '').toString());
      }
    } catch (e) {
      if (mounted) toast(context, 'مقدرناش نغيرها: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return Scaffold(appBar: AppBar(), body: const Loading());
    final disabled = m['disabled'] == true;
    final st = (m['storeId'] ?? kMainStore).toString();
    return Scaffold(
      appBar: AppBar(title: Text((m['shopName'] ?? 'مستخدم').toString())),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Avatar(m['photo'], radius: 40)),
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(m['role'] == 'owner' ? Icons.workspace_premium : Icons.person),
              title: Text(m['role'] == 'owner' ? 'صاحب محل' : 'عميل'),
              subtitle: Text('المحل: ${widget.stores[st] ?? st}'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text((m['username'] ?? m['email'] ?? '').toString(),
                  textDirection: TextDirection.ltr),
              subtitle: Text((m['password'] ?? '').toString().isEmpty
                  ? 'كلمة السر مش متسجلة'
                  : 'كلمة السر: ${m['password']}'),
              trailing: TextButton(onPressed: changePass, child: const Text('تغيير')),
            ),
          ]),
        ),
        SwitchListTile(
          value: !disabled,
          activeColor: kSuccess,
          title: Text(disabled ? 'الحساب موقوف' : 'الحساب شغال',
              style: TextStyle(
                  color: disabled ? kDanger : kSuccess, fontWeight: FontWeight.bold)),
          subtitle: const Text('لو وقفته مش هيقدر يدخل التطبيق'),
          onChanged: (v) async {
            await db.collection('users').doc(widget.userId).update({'disabled': !v});
            setState(() => m['disabled'] = !v);
          },
        ),
        const SizedBox(height: 8),
        _f(shop, 'اسم المحل', Icons.storefront),
        _f(owner, 'الاسم', Icons.person_outline),
        _f(phone, 'الموبايل', Icons.phone),
        _f(address, 'العنوان', Icons.home_outlined),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton(onPressed: busy ? null : save, child: const Text('حفظ')),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}

// ======================== الباقات والأسعار ========================

class PlansTab extends StatefulWidget {
  const PlansTab({super.key});
  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<Plan> plans = [];
  final payment = TextEditingController();
  bool signupOpen = true;
  bool loaded = false, busy = false;

  @override
  void initState() {
    super.initState();
    platformRef.get().then((s) {
      final c = PlatformConfig.fromMap(s.data());
      if (!mounted) return;
      setState(() {
        plans = [...c.plans];
        payment.text = c.paymentInfo;
        signupOpen = c.signupOpen;
        loaded = true;
      });
    });
  }

  Future<void> editPlan([int? i]) async {
    final p = i == null ? null : plans[i];
    final name = TextEditingController(text: p?.name ?? '');
    final months = TextEditingController(text: p == null ? '1' : '${p.months}');
    final price = TextEditingController(
        text: p == null ? '' : (p.price % 1 == 0 ? p.price.toStringAsFixed(0) : '${p.price}'));
    final note = TextEditingController(text: p?.note ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p == null ? 'باقة جديدة' : 'تعديل الباقة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الباقة')),
            const SizedBox(height: 8),
            TextField(
                controller: months,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المدة بالشهور')),
            const SizedBox(height: 8),
            TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'السعر (جنيه)')),
            const SizedBox(height: 8),
            TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'ملاحظة (زي: الأوفر)')),
          ]),
        ),
        actions: [
          if (p != null)
            TextButton(
                style: TextButton.styleFrom(foregroundColor: kDanger),
                onPressed: () => Navigator.pop(c, 'delete'),
                child: const Text('حذف')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('تمام')),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      if (r == 'delete' && i != null) {
        plans.removeAt(i);
      } else if (r == 'save') {
        final np = Plan(
            name: name.text.trim().isEmpty ? '${toI(months.text)} شهر' : name.text.trim(),
            months: toI(months.text) < 1 ? 1 : toI(months.text),
            price: toD(price.text),
            note: note.text.trim());
        if (i == null) {
          plans.add(np);
        } else {
          plans[i] = np;
        }
      }
    });
  }

  Future<void> save() async {
    if (plans.isEmpty) {
      toast(context, 'لازم باقة واحدة على الأقل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await platformRef.set(PlatformConfig(
              plans: plans, paymentInfo: payment.text.trim(), signupOpen: signupOpen)
          .toMap());
      if (mounted) toast(context, 'اتحفظت الباقات ✔');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Loading();
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('دي الباقات اللي هتظهر لأي محل عاوز يشترك في البرنامج وهو بيسجّل',
          style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 8),
      for (var i = 0; i < plans.length; i++)
        Card(
          child: ListTile(
            onTap: () => editPlan(i),
            leading: const CircleAvatar(
                backgroundColor: kPrimary, child: Icon(Icons.workspace_premium, color: kAccent)),
            title: Text('${plans[i].name}${plans[i].note.isEmpty ? '' : '  •  ${plans[i].note}'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(plans[i].period),
            trailing: Text(money(plans[i].price),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kSuccess)),
          ),
        ),
      OutlinedButton.icon(
          onPressed: () => editPlan(), icon: const Icon(Icons.add), label: const Text('باقة جديدة')),
      const SizedBox(height: 16),
      TextField(
        controller: payment,
        maxLines: 3,
        decoration: const InputDecoration(
            labelText: 'طريقة الدفع اللي هتظهر للمشترك',
            hintText: 'مثلاً: حوّل على فودافون كاش 010xxxxxxxx وابعت صورة التحويل واتساب'),
      ),
      SwitchListTile(
        value: signupOpen,
        onChanged: (v) => setState(() => signupOpen = v),
        title: const Text('استقبال طلبات اشتراك جديدة'),
        subtitle: const Text('لو قفلته، زرار "اشترك بمحلك" مش هيشتغل'),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 48,
        child: FilledButton(onPressed: busy ? null : save, child: const Text('حفظ الباقات')),
      ),
    ]);
  }
}

// ======================== سجل الاشتراكات ========================

class SubscriptionsTab extends StatelessWidget {
  const SubscriptionsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('subscriptions').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('${snap.error}');
        if (!snap.hasData) return const Loading();
        final docs = sortByDate(snap.data!.docs);
        final total = docs.fold(0.0, (a, d) => a + toD(d.data()['price']));
        final now = DateTime.now();
        final month = DateTime(now.year, now.month);
        final thisMonth = docs
            .where((d) => (tsToDate(d.data()['createdAt']) ?? now).isAfter(month))
            .fold(0.0, (a, d) => a + toD(d.data()['price']));
        return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: StatTile('دخل الشهر', money(thisMonth),
                      icon: Icons.trending_up, color: kSuccess)),
              Expanded(
                  child: StatTile('إجمالي الدخل', money(total), icon: Icons.savings)),
            ]),
          ),
          if (docs.isEmpty) const EmptyView('لسه مفيش اشتراكات مدفوعة'),
          for (final d in docs)
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: kSuccess),
                title: Text('${d.data()['storeName']} — ${d.data()['plan']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${fmtDate(d.data()['createdAt'])} • من ${fmtDate(d.data()['from'])} لحد ${fmtDate(d.data()['to'])}'),
                trailing: Text(money(d.data()['price']),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ]);
      },
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
          'status': 'active',
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
