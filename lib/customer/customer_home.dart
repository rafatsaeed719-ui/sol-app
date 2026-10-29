import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/fx.dart';
import '../core/push.dart';
import '../core/data.dart';
import '../shared/chat_screen.dart';
import '../shared/notifications.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'catalog_screen.dart';
import 'home_tab.dart';
import '../shared/messages.dart';
import 'my_orders_screen.dart';
import 'offers_screen.dart';

const String kSolWelcome =
    'عالم من العطور الفاخرة، حيث كل رشة بتحكي عنك، وكل عطر بيسيب بصمة متتنسيش. ❤️\n\nاكتشف عطرك، وخلّي حضورك مختلف.';

String get welcomeText {
  final w = (Session.store['welcome'] ?? '').toString();
  if (w.isNotEmpty) return w;
  return sid == kMainStore ? kSolWelcome : 'اطلب بضاعتك بسهولة، وتابع فواتيرك ونقاطك من مكان واحد 🙏';
}

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int tab = 0;
  bool welcomeChecked = false;

  @override
  void initState() {
    super.initState();
    setupPush(['all_$sid', pushTopic(uid)]);
  }

  /// رسالة الترحيب — بتظهر مرة واحدة بس أول ما المحل يسجّل
  void _maybeWelcome(Map<String, dynamic> me) {
    if (welcomeChecked || me.isEmpty) return;
    welcomeChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (me['welcomeShown'] != true) {
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
              const StoreLogo(size: 120, radius: 14),
              const SizedBox(height: 16),
              Text('✨ أهلاً بيك في $storeName ✨',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: kAccent, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Text(welcomeText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6)),
              if (storeSlogan.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('$storeName — $storeSlogan 💎',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: kAccent, fontSize: 17, fontWeight: FontWeight.w600)),
              ],
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
      }
      // الرسالة الخاصة وآخر إعلان
      if (mounted) await showPendingMessages(context, me);
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
          void openChat() => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      customerId: uid,
                      title: 'كلّم $storeName',
                      customerName: (me['shopName'] ?? '').toString())));
          final pages = [
            HomeTab(onGo: (i) => setState(() => tab = i), onChat: openChat),
            const CatalogScreen(),
            const OffersScreen(),
            const MyOrdersScreen(),
            AccountScreen(me: me),
          ];
          const titles = ['الرئيسية', 'المنتجات', 'العروض', 'طلباتي', 'حسابي'];
          return Scaffold(
            appBar: AppBar(
              title: Text(tab == 0 ? storeName : titles[tab],
                  style: tab == 0
                      ? const TextStyle(
                          fontWeight: FontWeight.w900, color: kAccent)
                      : null),
              actions: [
                IconButton(
                    tooltip: 'كلّمنا', onPressed: openChat, icon: const Icon(Icons.chat_bubble_outline)),
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
            floatingActionButton: tab <= 2
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
              destinations: [
                nav3D(Icons.home, 'الرئيسية'),
                nav3D(Icons.storefront, 'المنتجات'),
                nav3D(Icons.local_offer, 'العروض'),
                nav3D(Icons.receipt_long, 'طلباتي'),
                nav3D(Icons.person, 'حسابي'),
              ],
            ),
          );
        },
      ),
    );
  }
}
