import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/chat_screen.dart';
import '../shared/notifications.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'catalog_screen.dart';
import 'my_orders_screen.dart';
import 'offers_screen.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int tab = 0;
  bool welcomeChecked = false;

  /// رسالة الترحيب — بتظهر مرة واحدة بس أول ما المحل يسجّل
  void _maybeWelcome(Map<String, dynamic> me) {
    if (welcomeChecked || me.isEmpty) return;
    welcomeChecked = true;
    if (me['welcomeShown'] == true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => Dialog(
          backgroundColor: kPrimary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: kAccent, width: 1.2)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/logo.png', width: 120, height: 120),
              ),
              const SizedBox(height: 16),
              const Text('✨ أهلاً بيك في SOL ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kAccent, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              const Text(
                  'عالم من العطور الفاخرة، حيث كل رشة بتحكي عنك، وكل عطر بيسيب بصمة متتنسيش. ❤️',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16, height: 1.6)),
              const SizedBox(height: 12),
              const Text('اكتشف عطرك، وخلّي حضورك مختلف.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 16),
              const Text('SOL — عطرك، بصمتك. 💎',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kAccent, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kAccent, foregroundColor: kPrimary),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('يلا نبدأ',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      );
      try {
        await db.collection('users').doc(uid).update({'welcomeShown': true});
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotifListener(
      child: StreamBuilder(
        stream: db.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final me = snap.data?.data() ?? <String, dynamic>{};
          _maybeWelcome(me);
          final pages = [
            const CatalogScreen(),
            const OffersScreen(),
            const MyOrdersScreen(),
            AccountScreen(me: me),
            ChatView(customerId: uid, customerName: me['shopName'] ?? ''),
          ];
          const titles = ['المنتجات', 'العروض', 'طلباتي', 'حسابي', 'كلّمنا'];
          return Scaffold(
            appBar: AppBar(
              title: Text(tab == 0 ? 'SOL' : titles[tab],
                  style: tab == 0
                      ? const TextStyle(
                          fontWeight: FontWeight.w900, letterSpacing: 2, color: kAccent)
                      : null),
              actions: [
                const NotifBell(),
                ListenableBuilder(
                  listenable: Cart.I,
                  builder: (c, _) => IconButton(
                    tooltip: 'السلة',
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CartScreen(me: me))),
                    icon: Badge(
                      isLabelVisible: Cart.I.count > 0,
                      label: Text('${Cart.I.count}'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                  ),
                ),
              ],
            ),
            body: IndexedStack(index: tab, children: pages),
            floatingActionButton: tab <= 1
                ? ListenableBuilder(
                    listenable: Cart.I,
                    builder: (c, _) => Cart.I.count == 0
                        ? const SizedBox()
                        : FloatingActionButton.extended(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CartScreen(me: me))),
                            icon: const Icon(Icons.shopping_cart_checkout),
                            label: Text('اطلب (${money(Cart.I.total)})'),
                          ),
                  )
                : null,
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'المنتجات'),
                NavigationDestination(icon: Icon(Icons.local_offer_outlined), label: 'العروض'),
                NavigationDestination(icon: Icon(Icons.receipt_outlined), label: 'طلباتي'),
                NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
                NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'كلّمنا'),
              ],
            ),
          );
        },
      ),
    );
  }
}
