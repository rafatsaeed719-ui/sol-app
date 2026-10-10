import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/chat_screen.dart';

class ChatsAdmin extends StatelessWidget {
  const ChatsAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثات')),
      body: StreamBuilder(
        stream: db.collection('chats').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final docs = sortByDate(
              snap.data!.docs.where((d) => d.data()['lastAt'] != null).toList(),
              field: 'lastAt');
          if (docs.isEmpty) {
            return const EmptyView('مفيش محادثات لسه', icon: Icons.chat_bubble_outline);
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final m = docs[i].data();
              final unread = toI(m['unreadAdmin']);
              final name = (m['customerName'] ?? 'عميل').toString();
              return Card(
                child: ListTile(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(customerId: docs[i].id, title: name))),
                  leading: const CircleAvatar(child: Icon(Icons.storefront)),
                  title: Text(name,
                      style: TextStyle(
                          fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(m['lastMessage'] ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtDate(m['lastAt']), style: const TextStyle(fontSize: 11)),
                      if (unread > 0) Badge(label: Text('$unread')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
