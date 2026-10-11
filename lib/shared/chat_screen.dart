import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';

class ChatView extends StatefulWidget {
  final String customerId;
  final String customerName;
  const ChatView({super.key, required this.customerId, this.customerName = ''});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final text = TextEditingController();
  bool sending = false;

  @override
  void initState() {
    super.initState();
    markChatRead(widget.customerId);
  }

  Future<void> send() async {
    final t = text.text.trim();
    if (t.isEmpty) return;
    setState(() => sending = true);
    try {
      await sendMessage(widget.customerId, t, customerName: widget.customerName);
      text.clear();
      if (!isAdmin) {
        await notify('admin', 'رسالة من ${widget.customerName}', t,
            type: 'chat', refId: widget.customerId);
      } else {
        await notify(widget.customerId, 'رسالة من $storeName 💬', t,
            type: 'chat', refId: widget.customerId);
      }
    } catch (e) {
      if (mounted) toast(context, 'الرسالة متبعتتش: $e', error: true);
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final mine = isAdmin ? 'admin' : widget.customerId;
    return Column(children: [
      Expanded(
        child: StreamBuilder(
          stream: db
              .collection('chats')
              .doc(widget.customerId)
              .collection('messages')
              .orderBy('createdAt', descending: true)
              .limit(200)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
            if (!snap.hasData) return const Loading();
            final docs = snap.data!.docs;
            if (docs.isNotEmpty) markChatRead(widget.customerId);
            if (docs.isEmpty) {
              return EmptyView(
                  isAdmin ? 'ابدأ المحادثة' : 'اكتب لنا أي استفسار وهنرد عليك',
                  icon: Icons.chat_bubble_outline);
            }
            return ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(10),
              itemCount: docs.length,
              itemBuilder: (c, i) {
                final d = docs[i].data();
                final me = d['from'] == mine;
                return Align(
                  alignment:
                      me ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: me ? kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: me ? null : Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['text'] ?? '',
                            style: TextStyle(color: me ? Colors.white : Colors.black87)),
                        const SizedBox(height: 2),
                        Text(fmtDate(d['createdAt'], time: true),
                            style: TextStyle(
                                fontSize: 10,
                                color: me ? Colors.white60 : Colors.black45)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: text,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'اكتب رسالة...'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: sending ? null : send,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class ChatScreen extends StatelessWidget {
  final String customerId;
  final String title;
  const ChatScreen({super.key, required this.customerId, required this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ChatView(customerId: customerId, customerName: title),
    );
  }
}
