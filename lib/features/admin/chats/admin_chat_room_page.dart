import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AdminChatRoomPage extends StatefulWidget {
  const AdminChatRoomPage({
    super.key,
    required this.roomId,
    required this.otherUid,
  });

  final String roomId;
  final String otherUid;

  @override
  State<AdminChatRoomPage> createState() => _AdminChatRoomPageState();
}

class _AdminChatRoomPageState extends State<AdminChatRoomPage> {
  String get _otherUid =>
      (widget.otherUid.isNotEmpty) ? widget.otherUid : widget.roomId;

  final _ctl = TextEditingController();
  final _listCtl = ScrollController();
  bool _sending = false;
  final _picker = ImagePicker();

  CollectionReference<Map<String, dynamic>> get _chats =>
      FirebaseFirestore.instance.collection('chats');

  Query<Map<String, dynamic>> _messageQuery() =>
      _chats.doc(widget.roomId).collection('messages').orderBy('createdAt', descending: false);

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamMessages() =>
      _messageQuery().snapshots();

  @override
  void initState() {
    super.initState();
    assert(widget.roomId.isNotEmpty, 'roomId must not be empty');
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAdminRead());
  }

  @override
  void dispose() {
    _ctl.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  // ---------------- UI helpers ----------------
  Widget _userAvatarSmall() {
    final cs = Theme.of(context).colorScheme;
    if (_otherUid.isEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: cs.surfaceTint.withOpacity(.25),
        child: Icon(Icons.person, size: 16, color: cs.primary),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(_otherUid).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        final b64 = (m?['photoB64'] as String?) ?? '';
        if (b64.startsWith('data:image')) {
          try {
            final bytes = base64Decode(b64.split(',').last);
            return CircleAvatar(radius: 14, backgroundImage: MemoryImage(bytes));
          } catch (_) {}
        }
        return CircleAvatar(
          radius: 14,
          backgroundColor: cs.surfaceTint.withOpacity(.25),
          child: Icon(Icons.person, size: 16, color: cs.primary),
        );
      },
    );
  }

  Widget _adminAvatarSmall() {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 14,
      backgroundColor: cs.primaryContainer.withOpacity(.7),
      child: Icon(Icons.support_agent, size: 16, color: cs.onPrimaryContainer),
    );
  }

  // ---------------- read receipts ----------------
  Future<void> _markAdminRead() async {
    if (_otherUid.isEmpty) return;

    final roomRef = _chats.doc(widget.roomId);
    final msgsRef = roomRef.collection('messages');
    final qs = await msgsRef.where('senderId', isEqualTo: _otherUid).get();
    final batch = FirebaseFirestore.instance.batch();

    for (final d in qs.docs) {
      final m = d.data();
      final readBy =
          (m['readBy'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      final readByAdmin = (m['readByAdmin'] == true);
      if (!readBy.contains('admin') || !readByAdmin) {
        batch.set(d.reference, {
          'readBy': FieldValue.arrayUnion(['admin']),
          'readByAdmin': true,
        }, SetOptions(merge: true));
      }
    }

    batch.set(roomRef, {
      'unreadForAdmin': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ---------------- Sending Text ----------------
  Future<void> _send() async {
    if (_ctl.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);

    try {
      final now = FieldValue.serverTimestamp();
      final roomRef = _chats.doc(widget.roomId);
      final msgRef = roomRef.collection('messages').doc();

      await msgRef.set({
        'id': msgRef.id,
        'text': _ctl.text.trim(),
        'type': 'text',
        'from': 'admin',
        'senderId': 'admin',
        'createdAt': now,
        'readBy': ['admin'],
        'readByAdmin': true,
      });

      await roomRef.set({
        'roomId': widget.roomId,
        'participants': FieldValue.arrayUnion(['admin', widget.roomId]),
        'lastMessage': _ctl.text.trim(),
        'lastSender': 'admin',
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(1),
      }, SetOptions(merge: true));

      _ctl.clear();
      await Future.delayed(const Duration(milliseconds: 60));
      _scrollToBottom();
    } finally {
      setState(() => _sending = false);
    }
  }

  // ---------------- Sending Images ----------------
  Future<void> _sendImage() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    final now = FieldValue.serverTimestamp();
    final roomRef = _chats.doc(widget.roomId);
    final msgRef = roomRef.collection('messages').doc();

    if (images.length == 1) {
      // ส่งรูปเดียว
      final bytes = await images[0].readAsBytes();
      await msgRef.set({
        'id': msgRef.id,
        'type': 'image',
        'image': base64Encode(bytes),
        'from': 'admin',
        'senderId': 'admin',
        'createdAt': now,
        'readBy': ['admin'],
        'readByAdmin': true,
      });

      await roomRef.set({
        'roomId': widget.roomId,
        'participants': FieldValue.arrayUnion(['admin', widget.roomId]),
        'lastMessage': '📸 ส่งรูป 1 รูป',
        'lastSender': 'admin',
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } else {
      // ส่งหลายรูป
      final List<String> base64Images = [];
      for (final img in images) {
        final bytes = await img.readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      await msgRef.set({
        'id': msgRef.id,
        'type': 'images',
        'images': base64Images,
        'from': 'admin',
        'senderId': 'admin',
        'createdAt': now,
        'readBy': ['admin'],
        'readByAdmin': true,
      });

      await roomRef.set({
        'roomId': widget.roomId,
        'participants': FieldValue.arrayUnion(['admin', widget.roomId]),
        'lastMessage': '📸 ส่งรูป ${images.length} รูป',
        'lastSender': 'admin',
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }

    await Future.delayed(const Duration(milliseconds: 100));
    _scrollToBottom();
  }

  // ---------------- Scroll Helper ----------------
  void _scrollToBottom() {
    if (_listCtl.hasClients) {
      _listCtl.animateTo(
        _listCtl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------- Bubble ----------------
  //
  // 👈 ⭐⭐⭐ [START] โค้ด _buildBubble ที่คุณให้มา ⭐⭐⭐
  //
  Widget _buildBubble(Map<String, dynamic> m, bool isAdmin) {
    final cs = Theme.of(context).colorScheme;

    if (m['type'] == 'text') {
      return ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isAdmin ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isAdmin ? 14 : 4),
              bottomRight: Radius.circular(isAdmin ? 4 : 14),
            ),
          ),
          child: SelectableText(
            (m['text'] ?? '').toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // ถ้าหากเป็นรูปภาพ
    if (m['type'] == 'image') {
      final screenW = MediaQuery.of(context).size.width;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenW * 0.6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              base64Decode(m['image']),
              fit: BoxFit.contain,
              width: screenW * 0.55,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 80),
            ),
          ),
        ),
      );
    }

    // ถ้าหากมีหลายรูป
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
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
  // 
  // 👈 ⭐⭐⭐ [END] โค้ด _buildBubble ที่คุณให้มา ⭐⭐⭐
  //

  // ---------------- Date Header Helpers ----------------
  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = date.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  // ---------------- Date Header Widget ----------------
  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(

          stream: (_otherUid.isEmpty)
              ? const Stream.empty()
              : FirebaseFirestore.instance
                  .collection('users')
                  .doc(_otherUid)
                  .snapshots(),
          builder: (context, snap) {
            final m = snap.data?.data() ?? {};
            final name =
                (m['displayName'] ?? m['name'] ?? m['email'] ?? _otherUid)
                    .toString();

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _userAvatarSmall(),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamMessages(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อความ'));
                }

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _listCtl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final sender =
                        (m['senderId']?.toString() ?? m['from']?.toString() ?? '');
                    final isAdmin = sender == 'admin';

                    Widget? dateHeader;
                    final currentTs = m['createdAt'] as Timestamp?;
                    if (currentTs != null) {
                      final currentDt = currentTs.toDate();
                      if (i == 0) {
                        dateHeader = _buildDateHeader(_formatDateHeader(currentDt));
                      } else {
                        final prevTs =
                            docs[i - 1].data()['createdAt'] as Timestamp?;
                        if (prevTs != null) {
                          final prevDt = prevTs.toDate();
                          if (currentDt.day != prevDt.day ||
                              currentDt.month != prevDt.month ||
                              currentDt.year != prevDt.year) {
                            dateHeader =
                                _buildDateHeader(_formatDateHeader(currentDt));
                          }
                        }
                      }
                    }

                    String time = '';
                    if (currentTs != null) {
                      final dt = currentTs.toDate();
                      time =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    }

                    String? readLabel;
                    if (isAdmin && _otherUid.isNotEmpty) {
                      final readBy = (m['readBy'] as List? ?? const []);
                      readLabel = readBy.contains(_otherUid) ? 'Read' : 'Send';
                    }

                    final bubble = _buildBubble(m, isAdmin);

                    // 1. สร้าง Widget สำหรับ Metadata (เวลา และ สถานะ)
                    final Widget metadataContent = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(time, style: Theme.of(context).textTheme.labelSmall),
                        if (readLabel != null) // readLabel จะเป็น null ถ้าเป็น User
                          Text(
                            readLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: readLabel == 'Read'
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade600,
                                ),
                          ),
                      ],
                    );

                    // 2. สร้าง Row ของข้อความ
                    Widget messageRow;
                    if (isAdmin) {
                      // Layout Admin: [Metadata] [Bubble] [Avatar]
                      messageRow = Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          metadataContent, // 👈 Metadata อยู่ซ้าย
                          const SizedBox(width: 6),
                          Flexible(child: bubble), // 👈 Bubble อยู่กลาง
                          const SizedBox(width: 8),
                          _adminAvatarSmall(), // 👈 Avatar อยู่ขวา
                        ],
                      );
                    } else {
                      // Layout User: [Avatar] [Bubble] [Metadata]
                      messageRow = Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _userAvatarSmall(),
                          const SizedBox(width: 8),
                          Flexible(child: bubble),
                          const SizedBox(width: 6),
                          metadataContent,
                        ],
                      );
                    }

                    // 3. ส่งคืน Widget ทั้งหมดรวม Date Header (ถ้ามี)
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (dateHeader != null) dateHeader,
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Align(
                            alignment:
                                isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                            child: messageRow,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Material(
            elevation: 4,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        filled: true,
                        fillColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
