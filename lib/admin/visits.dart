import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../auth/location_picker.dart';
import '../core/app.dart';
import '../core/data.dart';
import 'customer_detail.dart';

const List<String> kVisitResults = [
  'أخد طلبية',
  'تحصيل فلوس',
  'متابعة',
  'عرض أصناف جديدة',
  'مرتجع',
  'المحل مقفول / مش موجود',
  'أخرى',
];

IconData visitIcon(String r) {
  switch (r) {
    case 'أخد طلبية':
      return Icons.shopping_cart;
    case 'تحصيل فلوس':
      return Icons.payments;
    case 'عرض أصناف جديدة':
      return Icons.new_releases;
    case 'مرتجع':
      return Icons.assignment_return;
    case 'المحل مقفول / مش موجود':
      return Icons.door_front_door;
  }
  return Icons.handshake;
}

/// عدد الأيام من آخر زيارة (null = عمره ما اتزار)
int? daysSinceVisit(Map<String, dynamic> customer) {
  final d = tsToDate(customer['lastVisitAt']);
  if (d == null) return null;
  return DateTime.now().difference(d).inDays;
}

String lastVisitText(Map<String, dynamic> customer) {
  final n = daysSinceVisit(customer);
  if (n == null) return 'عمره ما اتزار';
  if (n == 0) return 'اتزار النهارده';
  if (n == 1) return 'اتزار امبارح';
  return 'آخر زيارة من $n يوم';
}

Color lastVisitColor(Map<String, dynamic> customer) {
  final n = daysSinceVisit(customer);
  if (n == null || n > 30) return kDanger;
  if (n > 14) return Colors.orange;
  return kSuccess;
}

/// تسجيل زيارة لعميل
class VisitForm extends StatefulWidget {
  final String customerId;
  final Map<String, dynamic> customer;
  const VisitForm({super.key, required this.customerId, required this.customer});
  @override
  State<VisitForm> createState() => _VisitFormState();
}

class _VisitFormState extends State<VisitForm> {
  String result = kVisitResults[2];
  final note = TextEditingController();
  final amount = TextEditingController();
  DateTime? next;
  LatLng? here;
  bool locating = false, busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => locate());
  }

  Future<void> locate() async {
    setState(() => locating = true);
    final p = await currentLocation(context);
    if (mounted) {
      setState(() {
        here = p;
        locating = false;
      });
    }
  }

  double? get distance {
    final c = widget.customer;
    if (here == null || c['lat'] == null) return null;
    return const Distance().as(LengthUnit.Meter, here!, LatLng(toD(c['lat']), toD(c['lng'])));
  }

  Future<void> save() async {
    if (note.text.trim().isEmpty && result == 'أخرى') {
      toast(context, 'اكتب تعليق على الزيارة', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final name = (widget.customer['shopName'] ?? widget.customer['ownerName'] ?? '').toString();
      await db.collection('visits').add({
        'storeId': sid,
        'customerId': widget.customerId,
        'customerName': name,
        'result': result,
        'note': note.text.trim(),
        'amount': toD(amount.text),
        'nextVisit': next == null ? null : Timestamp.fromDate(next!),
        'lat': here?.latitude,
        'lng': here?.longitude,
        'distance': distance?.round(),
        'by': auth.currentUser?.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await db.collection('users').doc(widget.customerId).update({
        'lastVisitAt': Timestamp.fromDate(now),
        'lastVisitResult': result,
        'lastVisitNote': note.text.trim(),
        'nextVisit': next == null ? FieldValue.delete() : Timestamp.fromDate(next!),
      });
      if (mounted) {
        toast(context, 'اتسجلت الزيارة ✔');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final dist = distance;
    return Scaffold(
      appBar: AppBar(title: Text('زيارة: ${c['shopName'] ?? ''}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.history, color: lastVisitColor(c)),
            title: Text(lastVisitText(c)),
            subtitle: (c['lastVisitNote'] ?? '').toString().isEmpty
                ? null
                : Text('آخر تعليق: ${c['lastVisitNote']}'),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.my_location,
                color: here == null ? Colors.grey : (dist != null && dist > 300 ? Colors.orange : kSuccess)),
            title: Text(locating
                ? 'بنحدد مكانك...'
                : here == null
                    ? 'مقدرناش نحدد مكانك'
                    : dist == null
                        ? 'اتسجل مكانك (المحل ملوش موقع متسجل)'
                        : dist < 1000
                            ? 'إنت على بعد ${dist.round()} متر من المحل'
                            : 'إنت على بعد ${(dist / 1000).toStringAsFixed(1)} كم من المحل'),
            trailing: IconButton(onPressed: locating ? null : locate, icon: const Icon(Icons.refresh)),
          ),
        ),
        const SizedBox(height: 14),
        const Text('نتيجة الزيارة', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in kVisitResults)
            ChoiceChip(
              avatar: Icon(visitIcon(r), size: 18),
              label: Text(r),
              selected: result == r,
              onSelected: (_) => setState(() => result = r),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'التعليق على الزيارة',
              hintText: 'حصل إيه؟ العميل طلب إيه؟ محتاج إيه المرة الجاية؟'),
        ),
        if (result == 'تحصيل فلوس') ...[
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'المبلغ (للتسجيل في الزيارة بس)',
                helperText: 'عشان التحصيل يتخصم من الفاتورة سجّله من صفحة الفاتورة'),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.event_repeat, color: kAccent),
            title: Text(next == null ? 'الزيارة الجاية: مش محددة' : 'الزيارة الجاية: ${fmtDate(next)}'),
            trailing: next == null
                ? null
                : IconButton(onPressed: () => setState(() => next = null), icon: const Icon(Icons.clear)),
            onTap: () async {
              final p = await showDatePicker(
                  context: context,
                  initialDate: next ?? DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2035));
              if (p != null) setState(() => next = p);
            },
          ),
        ),
        Wrap(spacing: 6, children: [
          for (final d in const [3, 7, 14, 30])
            ActionChip(
                label: Text('بعد $d يوم'),
                onPressed: () => setState(() => next = DateTime.now().add(Duration(days: d)))),
        ]),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: busy ? null : save,
              icon: const Icon(Icons.check),
              label: const Text('تسجيل الزيارة'),
            ),
          ),
        ),
      ),
    );
  }
}

class VisitTile extends StatelessWidget {
  final Map<String, dynamic> v;
  final bool showCustomer;
  final String? id;
  const VisitTile(this.v, {super.key, this.showCustomer = false, this.id});

  @override
  Widget build(BuildContext context) {
    final r = (v['result'] ?? '').toString();
    final dist = v['distance'];
    return Card(
      child: ListTile(
        onTap: !showCustomer
            ? null
            : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => CustomerDetail(customerId: v['customerId']))),
        onLongPress: id == null
            ? null
            : () async {
                if (await confirm(context, 'حذف الزيارة', 'متأكد؟')) {
                  await db.collection('visits').doc(id).delete();
                }
              },
        leading: CircleAvatar(
          backgroundColor: kAccent.withValues(alpha: 0.15),
          child: Icon(visitIcon(r), color: kPrimary),
        ),
        title: Text(showCustomer ? '${v['customerName']} — $r' : r,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          fmtDate(v['createdAt'], time: true),
          if ((v['note'] ?? '').toString().isNotEmpty) '💬 ${v['note']}',
          if (toD(v['amount']) > 0) 'المبلغ: ${money(v['amount'])}',
          if (v['nextVisit'] != null) 'الجاية: ${fmtDate(v['nextVisit'])}',
          if (dist != null) 'على بعد $dist م من المحل',
        ].join('\n')),
        isThreeLine: true,
      ),
    );
  }
}

/// زيارات عميل واحد
class CustomerVisitsTab extends StatelessWidget {
  final String customerId;
  final Map<String, dynamic> customer;
  const CustomerVisitsTab({super.key, required this.customerId, required this.customer});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('visits').where('customerId', isEqualTo: customerId).snapshots(),
      builder: (context, s) {
        if (s.hasError) return EmptyView('${s.error}');
        if (!s.hasData) return const Loading();
        final docs = sortByDate(s.data!.docs);
        return ListView(padding: const EdgeInsets.only(top: 8, bottom: 90), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kPrimary),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => VisitForm(customerId: customerId, customer: customer))),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('سجّل زيارة'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.history, color: lastVisitColor(customer)),
              title: Text(lastVisitText(customer)),
              subtitle: Text('عدد الزيارات: ${docs.length}'
                  '${customer['nextVisit'] == null ? '' : ' • الجاية: ${fmtDate(customer['nextVisit'])}'}'),
            ),
          ),
          if (docs.isEmpty) const EmptyView('لسه مفيش زيارات', icon: Icons.location_off),
          for (final d in docs) VisitTile(d.data(), id: d.id),
        ]);
      },
    );
  }
}

/// كل الزيارات + العملاء اللي محتاجين زيارة
class VisitsScreen extends StatelessWidget {
  const VisitsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الزيارات'),
          bottom: const TabBar(
            labelColor: kAccent,
            unselectedLabelColor: Colors.white70,
            indicatorColor: kAccent,
            tabs: [Tab(text: 'مطلوب زيارتهم'), Tab(text: 'محتاجين زيارة'), Tab(text: 'السجل')],
          ),
        ),
        body: const TabBarView(children: [_DueTab(), _NeedVisitTab(), _LogTab()]),
      ),
    );
  }
}

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

Widget _customerVisitCard(BuildContext context, String id, Map<String, dynamic> m, {String? extra}) {
  final c = lastVisitColor(m);
  return Card(
    child: ListTile(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: id))),
      leading: Avatar(m['photo']),
      title: Text((m['shopName'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text([
        lastVisitText(m),
        if ((m['lastVisitNote'] ?? '').toString().isNotEmpty) '💬 ${m['lastVisitNote']}',
        if (extra != null) extra,
      ].join('\n')),
      isThreeLine: (m['lastVisitNote'] ?? '').toString().isNotEmpty || extra != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (m['lat'] != null)
          IconButton(
            tooltip: 'وديني',
            icon: const Icon(Icons.directions, color: kPrimary),
            onPressed: () => openDirections(toD(m['lat']), toD(m['lng'])),
          ),
        IconButton(
          tooltip: 'سجّل زيارة',
          icon: Icon(Icons.add_location_alt, color: c),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => VisitForm(customerId: id, customer: m))),
        ),
      ]),
    ),
  );
}

class _DueTab extends StatelessWidget {
  const _DueTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('users').snapshots(),
      builder: (context, s) {
        if (s.hasError) return EmptyView('${s.error}');
        if (!s.hasData) return const Loading();
        final end = DateTime.now();
        final today = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
        final _Docs list = s.data!.docs.where((d) {
          final n = tsToDate(d.data()['nextVisit']);
          return d.data()['role'] != 'owner' && n != null && n.isBefore(today);
        }).toList()
          ..sort((a, b) => tsToDate(a.data()['nextVisit'])!.compareTo(tsToDate(b.data()['nextVisit'])!));
        if (list.isEmpty) {
          return const EmptyView('مفيش زيارات مطلوبة النهارده 👌\nلما تسجّل زيارة حدد "الزيارة الجاية" وهتظهر هنا في ميعادها',
              icon: Icons.event_available);
        }
        return ListView(padding: const EdgeInsets.only(top: 8, bottom: 20), children: [
          for (final d in list)
            _customerVisitCard(context, d.id, d.data(),
                extra: '📅 كان المفروض: ${fmtDate(d.data()['nextVisit'])}'),
        ]);
      },
    );
  }
}

class _NeedVisitTab extends StatefulWidget {
  const _NeedVisitTab();
  @override
  State<_NeedVisitTab> createState() => _NeedVisitTabState();
}

class _NeedVisitTabState extends State<_NeedVisitTab> {
  int days = 14;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('users').snapshots(),
      builder: (context, s) {
        if (s.hasError) return EmptyView('${s.error}');
        if (!s.hasData) return const Loading();
        final _Docs list = s.data!.docs.where((d) {
          if (d.data()['role'] == 'owner') return false;
          final n = daysSinceVisit(d.data());
          return n == null || n >= days;
        }).toList()
          ..sort((a, b) => (daysSinceVisit(b.data()) ?? 99999).compareTo(daysSinceVisit(a.data()) ?? 99999));
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              children: [
                for (final d in const [7, 14, 30, 60])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                        label: Text('ماتزارش من $d يوم'),
                        selected: days == d,
                        onSelected: (_) => setState(() => days = d)),
                  ),
              ],
            ),
          ),
          if (list.isEmpty) const EmptyView('كل العملاء اتزاروا قريب 👌', icon: Icons.verified),
          for (final d in list) _customerVisitCard(context, d.id, d.data()),
        ]);
      },
    );
  }
}

class _LogTab extends StatefulWidget {
  const _LogTab();
  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  int days = 7;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('visits').snapshots(),
      builder: (context, s) {
        if (s.hasError) return EmptyView('${s.error}');
        if (!s.hasData) return const Loading();
        final from = DateTime.now().subtract(Duration(days: days));
        final list = sortByDate(s.data!.docs)
            .where((d) => days == 0 || (tsToDate(d.data()['createdAt']) ?? DateTime.now()).isAfter(from))
            .toList();
        final byResult = <String, int>{};
        for (final d in list) {
          final r = (d.data()['result'] ?? '').toString();
          byResult[r] = (byResult[r] ?? 0) + 1;
        }
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              children: [
                for (final p in const [
                  [1, 'النهارده'],
                  [7, 'أسبوع'],
                  [30, 'شهر'],
                  [0, 'الكل'],
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                        label: Text(p[1] as String),
                        selected: days == p[0],
                        onSelected: (_) => setState(() => days = p[0] as int)),
                  ),
              ],
            ),
          ),
          Card(
            color: kPrimary,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${list.length} زيارة',
                    style: const TextStyle(color: kAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 4, children: [
                  for (final e in byResult.entries)
                    Text('${e.key}: ${e.value}', style: const TextStyle(color: Colors.white70)),
                ]),
              ]),
            ),
          ),
          if (list.isEmpty) const EmptyView('مفيش زيارات في الفترة دي', icon: Icons.location_off),
          for (final d in list) VisitTile(d.data(), showCustomer: true, id: d.id),
        ]);
      },
    );
  }
}
