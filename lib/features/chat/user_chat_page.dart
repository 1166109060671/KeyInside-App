// lib/features/chat/user_chat_page.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/firestore_service.dart';

class UserChatPage extends StatefulWidget {
  const UserChatPage({super.key});

  @override
  State<UserChatPage> createState() => _UserChatPageState();
}

class _UserChatPageState extends State<UserChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- ส่งข้อความ ----------
  Future<void> _sendText() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _textController.text.trim();
    if (user == null || text.isEmpty) return;

    _textController.clear();
    await ChatApi(FirestoreService.instance)
        .sendUserText(uid: user.uid, text: text);

    _scrollToBottom();
  }

  // ---------- ส่งรูป ----------
  Future<void> _sendImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    // --- 🚀 เริ่มส่วนที่แก้ไข ---
    if (images.length == 1) {
      // กรณีรูปเดียว
      final bytes = await images[0].readAsBytes();
      final base64Image = base64Encode(bytes);

      // สมมติว่าคุณมี/สร้างฟังก์ชันนี้ใน ChatApi
      await ChatApi(FirestoreService.instance)
          .sendUserImage(uid: user.uid, base64Image: base64Image); // 👈 เรียกฟังก์ชันสำหรับรูปเดียว

    } else {
      // กรณีหลายรูป (เหมือนเดิม)
      List<String> base64Images = [];
      for (final image in images) {
        final bytes = await image.readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      await ChatApi(FirestoreService.instance)
          .sendUserImages(uid: user.uid, base64Images: base64Images); // 👈 เรียกฟังก์ชันสำหรับหลายรูป
    }
    // --- 🚀 จบส่วนที่แก้ไข ---

    _scrollToBottom(extraOffset: 120);
  }

  void _scrollToBottom({double extraOffset = 80}) {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + extraOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _markMessagesRead(
      String uid, List<QueryDocumentSnapshot<Map<String, dynamic>>> messages) async {
    final roomRef = FirebaseFirestore.instance.collection('chats').doc(uid);
    final batch = FirebaseFirestore.instance.batch();

    for (final doc in messages) {
      final data = doc.data();
      final sender = (data['senderId'] ?? data['from'] ?? '').toString();

      if (sender == 'admin') {
        final List readBy = (data['readBy'] as List?) ?? const [];
        if (!readBy.contains(uid) || (data['readByUser'] != true)) {
          batch.set(
            doc.reference,
            {
              'readBy': FieldValue.arrayUnion([uid]),
              'readByUser': true,
            },
            SetOptions(merge: true),
          );
        }
      }
    }

    batch.set(
      roomRef,
      {
        'unreadForUser': 0,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ---------- Avatar ----------
  Widget _adminAvatar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: cs.primaryContainer.withOpacity(.7),
      child: Icon(Icons.support_agent, size: 18, color: cs.onPrimaryContainer),
    );
  }

  Widget _userAvatar(BuildContext context, String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final b64 = (data?['photoB64'] as String?) ?? '';
        if (b64.startsWith('data:image')) {
          try {
            final bytes = base64Decode(b64.split(',').last);
            return CircleAvatar(radius: 16, backgroundImage: MemoryImage(bytes));
          } catch (_) {}
        }
        return CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          child: const Icon(Icons.person, size: 18),
        );
      },
    );
  }

  // ---------- สร้าง Bubble ----------
  Widget _buildBubble(Map<String, dynamic> m, bool isMine) {
    final cs = Theme.of(context).colorScheme;

    if (m['type'] == 'text') {
      return ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMine ? 14 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 14),
            ),
          ),
          child: SelectableText(
            (m['text'] ?? '').toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    if (m['type'] == 'image') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            base64Decode(m['image']),
            fit: BoxFit.contain,
            width: MediaQuery.of(context).size.width * 0.55,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
          ),
        ),
      );
    }

    if (m['type'] == 'images') {
      final List imgs = m['images'] ?? [];
      final crossCount = (imgs.length >= 2) ? 2 : imgs.length;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.55,
          height: (imgs.length / 2).ceil() * 120,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: imgs.length,
            itemBuilder: (_, i) {
              return GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                        child: Image.memory(
                          base64Decode(imgs[i]),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
                child: Image.memory(
                  base64Decode(imgs[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('โปรดล็อกอินเพื่อใช้งานแชท')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('แชทกับร้าน', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(user.uid)
                  .collection('messages')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markMessagesRead(user.uid, docs);
                });

                if (docs.isEmpty) {
                  return const Center(child: Text('เริ่มแชทกับร้านได้เลย 😊'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final msg = docs[i].data();
                    final sender = (msg['senderId'] ?? msg['from'] ?? '').toString();
                    final isMine = sender == user.uid;

                    String time = '';
                    final ts = msg['createdAt'];
                    if (ts is Timestamp) {
                      final t = ts.toDate();
                      time =
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                    }

                    String? readLabel;
                    if (isMine) {
                      final readBy = (msg['readBy'] as List? ?? const []);
                      readLabel = readBy.contains('admin') ? 'Read' : 'Send';
                    }

                    final bubble = _buildBubble(msg, isMine);

                    return Align(
                      alignment:
                          isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: isMine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: isMine
                              ? [
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(time,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.grey.shade600)),
                                            if (readLabel != null)
                                              Text(
                                                readLabel,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: readLabel == 'Read'
                                                      ? Colors.green
                                                      : Colors.grey.shade500,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.6,
                                          ),
                                          child: bubble,
                                        ),
                                        const SizedBox(width: 6),
                                        _userAvatar(context, user.uid),
                                      ],
                                    ),
                                  ),
                                ]
                              : [
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        _adminAvatar(context),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.6,
                                          ),
                                          child: bubble,
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(time,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.grey.shade600)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ---------- Input ----------
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                    onPressed: _sendImage,
                    icon: const Icon(Icons.image),
                    tooltip: 'เพิ่มรูปภาพ'),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: 'พิมพ์ข้อความ…',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _sendText, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
