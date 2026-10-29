import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app.dart';
import '../core/fx.dart';
import '../core/push.dart';
import '../core/data.dart';
import '../shared/notifications.dart';
import 'chats_admin.dart';
import '../shared/messages.dart';
import 'contacts_screen.dart';
import 'customers_admin.dart';
import 'dashboard_screen.dart';
import 'invoices_admin.dart';
import 'offers_admin.dart';
import 'orders_admin.dart';
import 'products_admin.dart';
import 'analytics_screen.dart';
import 'expenses_screen.dart';
import 'visits.dart';
import 'reports_screen.dart';
import 'store_profile.dart';
import 'storefront_editor.dart';
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
    setupPush(['admin_$sid', if (isSuper) 'super']);
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
      const _CustomersHub(),
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
                    nav3D(Icons.dashboard, 'الرئيسية'),
                    nav3D(Icons.shopping_cart, 'الطلبات',
                        wrap: (x) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: x)),
                    nav3D(Icons.storefront, 'العملاء'),
                    nav3D(Icons.inventory_2, 'الأصناف'),
                    nav3D(Icons.apps, 'المزيد',
                        wrap: (x) => Badge(
                            isLabelVisible: unreadChats > 0,
                            label: Text('$unreadChats'),
                            child: x)),
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
    var order = 0;
    const tones = [tGold, tBlue, tGreen, tPurple, tOrange, tTeal, tRed, tBlack];
    Widget item(IconData i, String t, String sub, Widget page, {Widget? badge}) {
      final k = order++;
      return FadeSlideIn(
        delayMs: 40 * k,
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Icon3D(i, size: 46, tone: tones[k % tones.length], delayMs: 60 * k),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(sub),
            trailing: badge ?? const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      if (isSuper)
        Card(
          color: kPrimary,
          child: ListTile(
            leading: const CircleAvatar(
                backgroundColor: kAccent, child: Icon(Icons.store_mall_directory, color: kPrimary)),
            title: const Text('إدارة البرنامج',
                style: TextStyle(fontWeight: FontWeight.bold, color: kAccent)),
            subtitle: Text(
                sid == kMainStore
                    ? 'المحلات، المستخدمين، الباقات والأسعار، الاشتراكات'
                    : 'إنت دلوقتي داخل على: $storeName',
                style: const TextStyle(color: Colors.white70)),
            trailing: StreamBuilder(
              stream: db.collection('stores').where('status', isEqualTo: 'pending').snapshots(),
              builder: (context, ps) {
                final n = ps.data?.docs.length ?? 0;
                return n > 0
                    ? Badge(label: Text('$n طلب'), backgroundColor: kAccent, textColor: kPrimary)
                    : const Icon(Icons.chevron_left, color: kAccent);
              },
            ),
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
      StreamBuilder(
        stream: scoped('users').snapshots(),
        builder: (context, us) {
          final now = DateTime.now();
          final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
          final due = (us.data?.docs ?? []).where((d) {
            final n = tsToDate(d.data()['nextVisit']);
            return n != null && n.isBefore(end);
          }).length;
          return item(Icons.location_history, 'الزيارات',
              'سجّل زيارة، آخر زيارة، مين محتاج يتزار', const VisitsScreen(),
              badge: due > 0 ? Badge(label: Text('$due النهارده')) : null);
        },
      ),
      item(Icons.insights, 'الرسومات البيانية', 'المبيعات والتحصيل والمصروفات بالرسم',
          const AnalyticsScreen()),
      item(Icons.warehouse, 'المخزن', 'الأرصدة، الوارد والصادر، اتحرك فين ولمين',
          const WarehouseScreen()),
      item(Icons.account_balance_wallet, 'المصروفات', 'اتصرف في إيه وكام ولمين',
          const ExpensesScreen()),
      item(Icons.campaign, 'الإعلانات والرسائل', 'رسالة أو إعلان يوصل لكل العملاء بإشعار',
          const AnnouncementsScreen()),
      item(Icons.local_offer, 'العروض', 'اعمل عرض ويوصل إشعار لكل العملاء',
          const OffersAdmin()),
      item(Icons.bar_chart, 'التقارير', 'حركة الأصناف، أكتر عميل، أكتر صنف',
          const ReportsScreen()),
      item(Icons.web, 'واجهة المتجر', 'البانرات وحكاية البراند والسوشيال',
          const StorefrontEditor()),
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


/// تبويب العملاء: حسابات التطبيق + دفتر العملاء (أرقام وعناوين)
class _CustomersHub extends StatelessWidget {
  const _CustomersHub();
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: kPrimary,
          indicatorColor: kAccent,
          tabs: [
            Tab(icon: Icon(Icons.phone_android), text: 'حسابات التطبيق'),
            Tab(icon: Icon(Icons.contacts), text: 'دفتر العملاء'),
          ],
        ),
        Expanded(child: TabBarView(children: [CustomersAdmin(), ContactsTab()])),
      ]),
    );
  }
}
