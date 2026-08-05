import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/chat.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../services/item_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'product_details_screen.dart';

/// In-app conversation thread (التواصل مع المتجر / الزبون).
/// History loads over REST; live messages are sent/received over the
/// WebSocket (`ws/chat/{chatId}/`), same pattern as AuctionDetailsScreen.
///
/// Three ways to open this screen:
/// - `store: Store` (from a store profile page) — resolves the chat id via
///   `createOrGetStoreChat`, as before.
/// - `chatId` + `title`/`avatarUrl` (from the conversations list) — the chat
///   already exists, so its id is used directly and `createOrGetStoreChat`
///   is skipped. Works for item-based and support chats too, since the
///   screen doesn't need to know which kind of chat it is once it has a
///   `chatId`.
/// - `isSupportChat: true` (from the account tab's "التواصل مع الدعم"
///   button) — resolves the chat id via `createOrGetSupportChat`; every
///   user has exactly one, so no id is needed up front.
class StoreChatScreen extends StatefulWidget {
  final Store? store;
  final int? chatId;
  final String? title;
  final String? avatarUrl;
  final bool isSupportChat;

  const StoreChatScreen({
    super.key,
    this.store,
    this.chatId,
    this.title,
    this.avatarUrl,
    this.isSupportChat = false,
  }) : assert(store != null || chatId != null || isSupportChat);

  @override
  State<StoreChatScreen> createState() => _StoreChatScreenState();
}

class _StoreChatScreenState extends State<StoreChatScreen> {
  final _service = ChatService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImage = false;
  String? _error;
  int? _myId;
  int? _chatId;
  String? _accessToken;
  Product? _item;
  final Set<int> _respondingToOffer = {};
  final Set<int> _redeemingOffer = {};
  bool _hasMoreMessages = false;
  bool _loadingOlderMessages = false;
  ChatConversation? _conversation;

  // مؤشر الكتابة: نُرسل حالتنا بعد تهدئة قصيرة (debounce) بدل كل ضغطة زر،
  // ونُخفي مؤشر الطرف الآخر تلقائياً إن لم يصل تحديث جديد خلال 5 ثوانٍ
  // (احتياطاً لحدث "توقف" مفقود، مثل إغلاق التطبيق فجأة أثناء الكتابة).
  bool _iAmTyping = false;
  Timer? _typingDebounce;
  bool _otherIsTyping = false;
  Timer? _otherTypingTimeout;

  // "متصل الآن": يبدأ من لقطة REST عند فتح المحادثة، ثم يتحدّث حيّاً عبر
  // حدث presence الذي يبثّه ChatConsumer عند اتصال/انقطاع الطرف الآخر.
  bool _otherOnline = false;

  /// عند الفتح عبر chatId فقط (كما من إشعار push) لا يُمرَّر عنوان جاهز —
  /// فنعتمد على `_conversation.displayTitle` بعد جلبه بدل ترك العنوان
  /// فارغاً بشكل دائم.
  bool get _isSupportChat => widget.isSupportChat || (_conversation?.isSupport ?? false);

  String get _title =>
      widget.store?.name ??
      widget.title ??
      _conversation?.displayTitle ??
      (_isSupportChat ? 'التواصل مع الدعم' : '');

  String? get _avatarUrl =>
      widget.store?.fullLogoUrl ?? widget.avatarUrl ?? _conversation?.displayAvatarUrl;

  @override
  void initState() {
    super.initState();
    _myId = context.read<AuthProvider>().user?.id;
    _controller.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _typingDebounce?.cancel();
    _otherTypingTimeout?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingOlderMessages || !_hasMoreMessages) {
      return;
    }
    if (_scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_messages.isEmpty || _accessToken == null || _chatId == null) return;
    setState(() => _loadingOlderMessages = true);

    final oldestId = _messages.first.id;
    final page = await _service.fetchOlderMessages(
      accessToken: _accessToken!,
      chatId: _chatId!,
      beforeMessageId: oldestId,
    );

    if (!mounted) return;
    if (page.results.isEmpty) {
      setState(() {
        _loadingOlderMessages = false;
        _hasMoreMessages = page.hasMore;
      });
      return;
    }

    // نحافظ على موضع التمرير المرئي: الرسائل الجديدة تُضاف أعلى القائمة،
    // فنُعوّض الفرق في ارتفاع المحتوى بعد إعادة البناء بدل القفز للأسفل.
    final oldExtent = _scrollController.position.maxScrollExtent;
    final oldPixels = _scrollController.position.pixels;
    setState(() {
      _messages.insertAll(0, page.results);
      _hasMoreMessages = page.hasMore;
      _loadingOlderMessages = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final newExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(oldPixels + (newExtent - oldExtent));
    });
  }

  void _onTextChanged() {
    if (!_isConnected || _channel == null) return;
    final hasText = _controller.text.trim().isNotEmpty;

    if (!hasText) {
      _typingDebounce?.cancel();
      if (_iAmTyping) {
        _iAmTyping = false;
        _sendTyping(false);
      }
      return;
    }

    if (!_iAmTyping) {
      _iAmTyping = true;
      _sendTyping(true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _iAmTyping = false;
      _sendTyping(false);
    });
  }

  void _sendTyping(bool isTyping) {
    try {
      _channel?.sink.add(jsonEncode({'type': 'typing', 'is_typing': isTyping}));
    } catch (_) {
      // اتصال منقطع لحظياً — لا داعٍ لإظهار خطأ لمجرد مؤشر الكتابة
    }
  }

  Future<void> _init() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    _accessToken = token;

    int chatId;
    if (widget.chatId != null) {
      chatId = widget.chatId!;
    } else {
      final result = widget.isSupportChat
          ? await _service.createOrGetSupportChat(accessToken: token)
          : await _service.createOrGetStoreChat(
              accessToken: token, storeId: widget.store!.id);
      if (!mounted) return;

      if (!result.success || result.chat == null) {
        setState(() {
          _loading = false;
          _error = result.message;
        });
        return;
      }
      chatId = result.chat!.id;
    }
    _chatId = chatId;

    final full = await _service.fetchChat(accessToken: token, chatId: chatId);
    if (!mounted) return;

    setState(() {
      _loading = false;
      _conversation = full;
      _item = full?.item;
      _otherOnline = full?.otherUserOnline ?? false;
      _hasMoreMessages = full?.hasMoreMessages ?? false;
      _messages
        ..clear()
        ..addAll(full?.messages ?? []);
    });
    _scrollToBottom();
    _connectWebSocket(chatId, token);
  }

  void _connectWebSocket(int chatId, String accessToken) {
    try {
      final url =
          Uri.parse(ApiConfig.wsUrl('/ws/chat/$chatId/?token=$accessToken'));
      _channel = WebSocketChannel.connect(url);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (_) {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect(chatId, accessToken);
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect(chatId, accessToken);
        },
      );

      _reconnectAttempts = 0;
      setState(() => _isConnected = true);
    } catch (_) {
      _scheduleReconnect(chatId, accessToken);
    }
  }

  /// A dropped connection is common on mobile networks — without this the
  /// chat just stops receiving new messages until the user manually leaves
  /// and reopens it. Backs off up to 30s so a genuinely offline device
  /// isn't hammered with reconnect attempts.
  void _scheduleReconnect(int chatId, String accessToken) {
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = [2, 4, 8, 16, 30][
        (_reconnectAttempts - 1).clamp(0, 4)];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && !_isConnected) _connectWebSocket(chatId, accessToken);
    });
  }

  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      if (data['type'] == 'message') {
        final message = ChatMessage.fromWsEvent(data);
        setState(() {
          // إن كانت هذه رسالتي أنا، فهي صدى لرسالة أُدرجت محلياً فوراً عند
          // الإرسال (انظر _send) — نستبدل أقدم فقاعة "معلّقة" بدل إضافة نسخة
          // مكرّرة. غير المطابقة (لا توجد فقاعة معلّقة، مثلاً بعد إعادة
          // اتصال) تُضاف كالعادة.
          final pendingIdx = message.senderId == _myId
              ? _messages.indexWhere((m) => m.isPending && m.senderId == _myId)
              : -1;
          if (pendingIdx != -1) {
            _messages[pendingIdx] = message;
          } else {
            _messages.add(message);
          }
        });
        _scrollToBottom();
      } else if (data['type'] == 'typing') {
        // الخادم (ChatConsumer.typing_indicator) لا يعيد بثّ حدث الكتابة إلى
        // مُرسله، فأي حدث نستلمه هنا هو دوماً من الطرف الآخر.
        _handleTypingEvent(data['is_typing'] as bool? ?? false);
      } else if (data['type'] == 'messages_read') {
        // بُثّ عند اتصال الطرف الآخر أو فتحه للمحادثة (mark_messages_read
        // على الخادم) — نُحدّث رسائلي أنا فقط إلى "مقروءة" محلياً.
        final readerId = data['reader_id'] as int?;
        if (readerId != null && readerId != _myId) {
          setState(() {
            for (var i = 0; i < _messages.length; i++) {
              if (_messages[i].senderId == _myId && !_messages[i].isRead) {
                _messages[i] = _messages[i].copyWith(isRead: true);
              }
            }
          });
        }
      } else if (data['type'] == 'presence') {
        // الخادم (ChatConsumer.presence_update) لا يعيد بثّ هذا الحدث إلى
        // مُرسله، فأي حدث نستلمه هنا هو دوماً من الطرف الآخر.
        final userId = data['user_id'] as int?;
        if (userId != null && userId != _myId) {
          setState(() => _otherOnline = data['is_online'] as bool? ?? false);
        }
      }
    } catch (_) {
      // تجاهل الرسائل غير المفهومة
    }
  }

  void _handleTypingEvent(bool isTyping) {
    _otherTypingTimeout?.cancel();
    setState(() => _otherIsTyping = isTyping);
    if (isTyping) {
      _scrollToBottom();
      _otherTypingTimeout = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _otherIsTyping = false);
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || !_isConnected || _channel == null) return;

    // صدى محلي فوري: بدون هذا، كانت رسالتي لا تظهر عندي إلا بعد رحلة كاملة
    // (أنا → الخادم → بثّ إلى المجموعة → عودة إلى اتصالي أنا)، بينما الطرف
    // الآخر يراها بعد نصف هذه الرحلة فقط (الخادم → هو) — فتظهر عنده أولاً.
    // تُستبدل هذه الفقاعة المؤقتة بالرسالة الفعلية فور وصول صداها (انظر
    // _handleMessage)، فتتحوّل أيقونة الساعة إلى علامة إرسال/قراءة حقيقية.
    final pendingId = -DateTime.now().microsecondsSinceEpoch;
    final optimistic =
        ChatMessage.pending(id: pendingId, senderId: _myId, content: text);

    setState(() => _messages.add(optimistic));
    _scrollToBottom();
    _controller.clear();

    setState(() => _sending = true);
    try {
      _channel!.sink.add(jsonEncode({'type': 'message', 'message': text}));
    } catch (_) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == pendingId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال الرسالة')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_uploadingImage || _chatId == null || _accessToken == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('من المعرض'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final image = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (image == null || !mounted) return;

    setState(() => _uploadingImage = true);
    final result = await _service.sendImageMessage(
      accessToken: _accessToken!,
      chatId: _chatId!,
      image: image,
    );
    if (!mounted) return;
    setState(() => _uploadingImage = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message.isEmpty ? 'تعذّر إرسال الصورة' : result.message)),
      );
    }
  }

  Future<void> _respondToOffer(ChatMessage m, {required bool accept}) async {
    if (_accessToken == null || _respondingToOffer.contains(m.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _respondingToOffer.add(m.id));

    final result = accept
        ? await _service.acceptOffer(accessToken: _accessToken!, messageId: m.id)
        : await _service.rejectOffer(accessToken: _accessToken!, messageId: m.id);

    if (!mounted) return;
    setState(() {
      _respondingToOffer.remove(m.id);
      if (result.success) {
        final idx = _messages.indexWhere((msg) => msg.id == m.id);
        if (idx != -1) {
          _messages[idx] = _messages[idx]
              .copyWith(offerStatus: accept ? 'accepted' : 'rejected');
        }
      }
    });

    if (!result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isEmpty ? 'تعذّر تنفيذ الطلب' : result.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _useOffer(ChatMessage m) async {
    if (_accessToken == null || _item == null || _redeemingOffer.contains(m.id)) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _redeemingOffer.add(m.id));

    final listing = await ItemService()
        .fetchListingByItemId(accessToken: _accessToken!, itemId: _item!.id);

    if (!mounted) return;
    setState(() => _redeemingOffer.remove(m.id));

    if (listing == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عرض سعر ثابت لهذا المنتج'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          listing: listing,
          acceptedOfferMessageId: m.id,
          acceptedOfferAmount: m.offerAmount,
          acceptedOfferQuantity: m.offerQuantity,
        ),
      ),
    );
  }

  void _openImageViewer(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              child: AppNetworkImage(url),
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  Widget _dateSeparator(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dayLabelAr(dt),
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceContainerLowest,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.surfaceContainerHigh),
          ),
          title: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.surfaceContainer,
                    backgroundImage: _avatarUrl != null
                        ? CachedNetworkImageProvider(_avatarUrl!)
                        : null,
                    child: _avatarUrl == null
                        ? Icon(
                            _isSupportChat ? Icons.support_agent : Icons.store,
                            size: 18,
                            color: AppColors.onSurfaceVariant)
                        : null,
                  ),
                  if (_otherOnline && !_isSupportChat)
                    Positioned(
                      bottom: -1,
                      left: -1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.surfaceContainerLowest, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_otherIsTyping)
                      const Text(
                        'يكتب الآن...',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _init();
              },
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              _messages.isEmpty
                  ? Center(
                      child: Text(
                        _isSupportChat
                            ? 'ابدأ المحادثة مع الدعم'
                            : 'ابدأ المحادثة مع المتجر',
                        style:
                            const TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_otherIsTyping ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _messages.length) {
                          // مؤشر الكتابة كفقاعة في المحادثة نفسها بدل الاكتفاء
                          // بسطر صغير تحت العنوان — أوضح بكثير وأصعب تفويتاً،
                          // وهو الشكل المعتاد في تطبيقات المحادثة.
                          return const _TypingBubble();
                        }
                        final m = _messages[i];
                        final isMine = _myId != null && m.senderId == _myId;
                        final showDateSeparator = i == 0 ||
                            !_isSameDay(
                                _messages[i - 1].createdAt, m.createdAt);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showDateSeparator) _dateSeparator(m.createdAt),
                            _bubble(m, isMine),
                          ],
                        );
                      },
                    ),
              if (_loadingOlderMessages)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
        _inputBar(),
      ],
    );
  }

  Widget _bubble(ChatMessage m, bool isMine) {
    if (m.isOffer) return _offerCard(m, isMine);
    final hasImage = m.attachmentUrl != null;
    // "الخاصة بي" على اليمين والطرف الآخر على اليسار (كما في واتساب/تيليجرام)
    // — هذه هي القناعة السائدة حتى في الواجهات العربية، بعكس ما كان مطبّقاً
    // سابقاً. زاوية علوية صغيرة (4) على جهة الفقاعة الملاصقة لحافة الشاشة
    // تُحاكي شكل "الذيل" المعتاد في فقاعات المحادثة.
    return Align(
      key: ValueKey(m.id),
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress:
            (isMine && !m.isPending) ? () => _showMessageActions(m) : null,
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: hasImage
            ? const EdgeInsets.all(6)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.primary
              : (hasImage
                  ? AppColors.surfaceContainerHigh
                  : AppColors.surfaceContainer),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(isMine ? 4 : 18),
            topLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: const Radius.circular(18),
            bottomLeft: const Radius.circular(18),
          ),
        ),
        child: Column(
          // "start" لا "stretch": الأخيرة كانت تُجبر كل فقاعة على أخذ كامل
          // الحدّ الأقصى (75% من عرض الشاشة) بصرف النظر عن طول الرسالة —
          // Column مع crossAxisAlignment.stretch يمرّر عرضاً مُلزَماً
          // (tightFor) لكل الأبناء يساوي أقصى عرض للأب، فتتمدّد الفقاعة
          // دوماً حتى لو كانت الرسالة كلمة واحدة. مع end تحتوي الفقاعة على
          // حجم أعرض أبنائها فقط (الرسالة نفسها عادةً) وتتمدّد فقط عند
          // الحاجة الفعلية (نص طويل يلتفّ لعدّة أسطر أو صورة).
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onTap: () => _openImageViewer(m.attachmentUrl!),
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: AppNetworkImage(
                        m.attachmentUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surfaceContainer,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined,
                              color: AppColors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (m.content.isNotEmpty)
              Padding(
                padding: hasImage
                    ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                    : EdgeInsets.zero,
                child: Text(
                  m.content,
                  style: TextStyle(
                    color: isMine ? AppColors.onPrimary : AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    shortTime(m.createdAt),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: (isMine
                              ? AppColors.onPrimary
                              : AppColors.onSurfaceVariant)
                          .withValues(alpha: 0.8),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      m.isPending
                          ? Icons.access_time
                          : (m.isRead ? Icons.done_all : Icons.done),
                      size: 14,
                      color: AppColors.onPrimary.withValues(
                          alpha: m.isPending ? 0.5 : (m.isRead ? 1 : 0.65)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _showMessageActions(ChatMessage m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('حذف الرسالة', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'delete' && mounted) _deleteMessage(m);
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    if (_accessToken == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: const Text('سيتم حذف هذه الرسالة من محادثتك. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result =
        await _service.deleteMessage(accessToken: _accessToken!, messageId: m.id);

    if (!mounted) return;
    if (result.success) {
      setState(() => _messages.removeWhere((msg) => msg.id == m.id));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isEmpty ? 'تعذّر حذف الرسالة' : result.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _offerCard(ChatMessage m, bool isMine) {
    final statusInfo = switch (m.offerStatus) {
      'accepted' => (label: 'مقبول', color: AppColors.success),
      'rejected' => (label: 'مرفوض', color: AppColors.error),
      _ => (label: 'بانتظار الرد', color: AppColors.tertiary),
    };
    final canRespond = !isMine && m.offerStatus == 'pending';
    final responding = _respondingToOffer.contains(m.id);

    return Align(
      key: ValueKey(m.id),
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.tertiaryContainer, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 15, color: AppColors.tertiary),
                const SizedBox(width: 6),
                const Text('عرض سعر',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tertiary)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusInfo.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusInfo.color)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_item != null)
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: _item!.firstImage != null
                          ? AppNetworkImage(_item!.firstImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                  color: AppColors.surfaceContainer))
                          : Container(color: AppColors.surfaceContainer),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_item!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface)),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('الكمية: ${m.offerQuantity ?? 1}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceVariant)),
                const Spacer(),
                Text(
                  formatIqd(m.offerAmount ?? 0),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryContainer),
                ),
              ],
            ),
            if (canRespond) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          responding ? null : () => _respondToOffer(m, accept: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          responding ? null : () => _respondToOffer(m, accept: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: responding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('قبول'),
                    ),
                  ),
                ],
              ),
            ],
            if (isMine && m.offerStatus == 'accepted' && !m.isRedeemed) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _redeemingOffer.contains(m.id)
                      ? null
                      : () => _useOffer(m),
                  icon: _redeemingOffer.contains(m.id)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.shopping_bag_outlined, size: 16),
                  label: const Text('احجز بهذا السعر'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  shortTime(m.createdAt),
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    final outlineFaint = AppColors.outline.withValues(alpha: 0.3);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: AppColors.surfaceContainerHigh)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.rtl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: _isConnected ? 'اكتب رسالة...' : 'جارٍ الاتصال...',
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  suffixIcon: _uploadingImage
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: _pickAndSendImage,
                          icon: const Icon(Icons.image_outlined,
                              color: AppColors.primary),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: outlineFaint),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: outlineFaint),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Icon(Icons.send,
                        color: AppColors.onPrimary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "يكتب الآن..." كفقاعة بثلاث نقاط متحرّكة بنفس تصميم فقاعة الرسالة
/// المستلمة — أوضح للمستخدم من سطر صغير تحت العنوان وحده.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // كل نقطة تنبض بعد سابقتها بفارق ثلث الدورة، فتُعطي إحساس
                // موجة متتابعة بدل نبض متزامن.
                final t = (_controller.value - (i * 1 / 3)) % 1.0;
                final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                return Padding(
                  padding: EdgeInsets.only(left: i == 2 ? 0 : 4),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
