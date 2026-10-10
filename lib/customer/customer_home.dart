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

  @override
  Widget build(BuildContext context) {
    return NotifListener(
      child: StreamBuilder(
        stream: db.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final me = snap.data?.data() ?? <String, dynamic>{};
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
