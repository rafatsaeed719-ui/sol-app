import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/notifications.dart';
import 'chats_admin.dart';
import 'customers_admin.dart';
import 'dashboard_screen.dart';
import 'invoices_admin.dart';
import 'offers_admin.dart';
import 'orders_admin.dart';
import 'products_admin.dart';
import 'expenses_screen.dart';
import 'reports_screen.dart';
import 'store_profile.dart';
import 'stores_admin.dart';
import 'warehouse_screen.dart';
import 'settings_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _overdueAlert());
  }

  /// مرة في اليوم: تنبيه بالعملاء اللي عدّى ميعاد تحصيلهم
  Future<void> _overdueAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = fmtDate(DateTime.now());
      if (prefs.getString('overdueAlert_$sid') == today) return;
      final snap = await scoped('invoices').get();
      final lateMap = <String, double>{};
      for (final d in snap.docs) {
        final m = d.data();
        if (isOverdue(m)) {
          final n = (m['customerName'] ?? '').toString();
          lateMap[n] = (lateMap[n] ?? 0) + toD(m['balance']);
        }
      }
      await prefs.setString('overdueAlert_$sid', today);
      if (lateMap.isEmpty || !mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.warning_amber, color: kDanger, size: 44),
          title: const Text('عملاء عدّى ميعاد تحصيلهم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: lateMap.entries
                  .map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, color: kDanger),
                        title: Text(e.key),
                        trailing: Text(money(e.value),
                            style: const TextStyle(
                                color: kDanger, fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('تمام')),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onGo: (i) => setState(() => tab = i)),
      const OrdersAdmin(),
      const CustomersAdmin(),
      const ProductsAdmin(),
      const _MoreMenu(),
    ];
    const titles = ['لوحة التحكم', 'الطلبات', 'العملاء', 'الأصناف', 'المزيد'];
    return NotifListener(
      child: Scaffold(
        appBar: AppBar(
          title: Text(tab == 0 ? '$storeName — الإدارة' : titles[tab]),
          actions: const [NotifBell()],
        ),
        body: IndexedStack(index: tab, children: pages),
        bottomNavigationBar: StreamBuilder(
          stream: scoped('orders').where('status', isEqualTo: 'new').snapshots(),
          builder: (context, s) {
            final n = s.data?.docs.length ?? 0;
            return StreamBuilder(
              stream: scoped('chats').snapshots(),
              builder: (context, cs) {
                final unreadChats = (cs.data?.docs ?? [])
                    .where((d) => toI(d.data()['unreadAdmin']) > 0)
                    .length;
                return NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  destinations: [
                    const NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
                    NavigationDestination(
                        icon: Badge(
                            isLabelVisible: n > 0,
                            label: Text('$n'),
                            child: const Icon(Icons.shopping_cart_outlined)),
                        label: 'الطلبات'),
                    const NavigationDestination(
                        icon: Icon(Icons.storefront_outlined), label: 'العملاء'),
                    const NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined), label: 'الأصناف'),
                    NavigationDestination(
                        icon: Badge(
                            isLabelVisible: unreadChats > 0,
                            label: Text('$unreadChats'),
                            child: const Icon(Icons.menu)),
                        label: 'المزيد'),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, String sub, Widget page, {Widget? badge}) => Card(
          child: ListTile(
            leading: CircleAvatar(
                backgroundColor: kPrimary.withValues(alpha: 0.1),
                child: Icon(i, color: kPrimary)),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(sub),
            trailing: badge ?? const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        );
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      if (isSuper)
        Card(
          color: kPrimary,
          child: ListTile(
            leading: const CircleAvatar(
                backgroundColor: kAccent, child: Icon(Icons.store_mall_directory, color: kPrimary)),
            title: const Text('إدارة المحلات',
                style: TextStyle(fontWeight: FontWeight.bold, color: kAccent)),
            subtitle: Text(
                sid == kMainStore ? 'المحلات المشتركة والاشتراكات' : 'إنت دلوقتي داخل على: $storeName',
                style: const TextStyle(color: Colors.white70)),
            trailing: const Icon(Icons.chevron_left, color: kAccent),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const StoresAdmin())),
          ),
        ),
      StreamBuilder(
        stream: scoped('chats').snapshots(),
        builder: (context, s) {
          final n = (s.data?.docs ?? [])
              .where((d) => toI(d.data()['unreadAdmin']) > 0)
              .length;
          return item(Icons.chat, 'المحادثات', 'رسائل العملاء', const ChatsAdmin(),
              badge: n > 0 ? Badge(label: Text('$n')) : null);
        },
      ),
      item(Icons.receipt_long, 'الفواتير والتحصيل', 'كل الفواتير، المتأخرات، الدفعات',
          const InvoicesAdmin(standalone: true)),
      item(Icons.warehouse, 'المخزن', 'الأرصدة، الوارد والصادر، اتحرك فين ولمين',
          const WarehouseScreen()),
      item(Icons.account_balance_wallet, 'المصروفات', 'اتصرف في إيه وكام ولمين',
          const ExpensesScreen()),
      item(Icons.local_offer, 'العروض', 'اعمل عرض ويوصل إشعار لكل العملاء',
          const OffersAdmin()),
      item(Icons.bar_chart, 'التقارير', 'حركة الأصناف، أكتر عميل، أكتر صنف',
          const ReportsScreen()),
      item(Icons.storefront, 'بيانات المحل', 'الاسم واللوجو ورسالة الترحيب',
          const StoreProfileScreen()),
      item(Icons.settings, 'الإعدادات', 'أيام التحصيل ونظام النقاط', const SettingsScreen()),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kDanger),
          onPressed: () async {
            if (await confirm(context, 'تسجيل خروج', 'عاوز تخرج؟')) await auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل خروج'),
        ),
      ),
    ]);
  }
}
