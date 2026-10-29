import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import 'customer_accounts.dart';
import 'customer_detail.dart';
import 'visits.dart';

class CustomersAdmin extends StatefulWidget {
  const CustomersAdmin({super.key});
  @override
  State<CustomersAdmin> createState() => _CustomersAdminState();
}

class _CustomersAdminState extends State<CustomersAdmin> {
  String q = '';
  String sort = 'balance';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addCustomer',
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AddCustomerScreen())),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة عميل'),
      ),
      body: _list(context),
    );
  }

  Widget _list(BuildContext context) {
    return StreamBuilder(
      stream: scoped('users').snapshots(),
      builder: (context, us) {
        if (us.hasError) return EmptyView('حصلت مشكلة: ${us.error}');
        if (!us.hasData) return const Loading();
        return StreamBuilder(
          stream: scoped('invoices').snapshots(),
          builder: (context, inv) {
            final byCustomer = <String, List<Map<String, dynamic>>>{};
            for (final d in inv.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final m = d.data();
              byCustomer.putIfAbsent(m['customerId'] ?? '', () => []).add(m);
            }
            final sums = {
              for (final e in byCustomer.entries) e.key: summarize(e.value),
            };
            var list = us.data!.docs.where((d) {
              if (d.data()['role'] == 'owner' || d.data()['deleted'] == true) return false;
              if (q.isEmpty) return true;
              final m = d.data();
              final hay = '${m['shopName']} ${m['ownerName']} ${m['phone']} ${m['address']}'
                  .toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();
            list.sort((a, b) {
              if (sort == 'name') {
                return (a.data()['shopName'] ?? '')
                    .toString()
                    .compareTo((b.data()['shopName'] ?? '').toString());
              }
              if (sort == 'visit') {
                return (daysSinceVisit(b.data()) ?? 99999)
                    .compareTo(daysSinceVisit(a.data()) ?? 99999);
              }
              if (sort == 'sales') {
                return (sums[b.id]?.total ?? 0).compareTo(sums[a.id]?.total ?? 0);
              }
              return (sums[b.id]?.balance ?? 0).compareTo(sums[a.id]?.balance ?? 0);
            });
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'دوّر باسم المحل أو الموبايل',
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
                    for (final s in const [
                      ['balance', 'الأكتر مديونية'],
                      ['sales', 'الأكتر شراء'],
                      ['name', 'بالاسم'],
                      ['visit', 'محتاج زيارة'],
                    ])
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                          label: Text(s[1]),
                          selected: sort == s[0],
                          onSelected: (_) => setState(() => sort = s[0]),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyView('مفيش عملاء لسه — أول ما محل يسجّل هيظهر هنا',
                        icon: Icons.storefront)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: list.length,
                        itemBuilder: (c, i) {
                          final m = list[i].data();
                          final s = sums[list[i].id] ?? AccountSummary();
                          return Card(
                            child: ListTile(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => CustomerDetail(customerId: list[i].id))),
                              leading: Avatar(m['photo']),
                              title: Text(m['shopName'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${m['ownerName'] ?? ''} • ${m['phone'] ?? ''}\nمشتريات ${money(s.total)} • ⭐ ${toI(m['points'])}\n📍 ${lastVisitText(m)}'),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(money(s.balance),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: s.balance > 0.009 ? Colors.orange : kSuccess)),
                                  if (s.overdueCount > 0)
                                    const Text('متأخر',
                                        style: TextStyle(color: kDanger, fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]);
          },
        );
      },
    );
  }
}
