import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/live_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/live_sessions_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/live_session_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/refreshable_tab.dart';
import '../../widgets/live/live_session_card.dart';
import 'create_live_session_screen.dart';
import 'live_broadcast_screen.dart';
import 'live_viewer_screen.dart';

class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({super.key});

  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen>
    implements RefreshableTab {
  static const _sortOptions = [
    ('-current_viewer_count', 'الأكثر مشاهدة'),
    ('-likes_count', 'الأكثر إعجاباً'),
    ('-started_at', 'الأحدث'),
  ];

  final _service = LiveSessionService();
  bool _checkingMyLiveSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Future<void> refreshTab() async => _load();

  void _load() {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    context.read<LiveSessionsProvider>().loadSessions(accessToken: token);
    // Fire-and-forget: needed to know whether to show the "go live" FAB.
    context.read<StoreProvider>().loadMyStore(accessToken: token);
  }

  /// Resumes an already-live session's control screen if the owner has one
  /// (e.g. they left the broadcast screen without hitting "End" — there'd
  /// otherwise be no way back in to end it), instead of always starting a
  /// brand-new session.
  Future<void> _goLivePressed() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    setState(() => _checkingMyLiveSession = true);
    LiveSession? existingLive;
    try {
      final mySessions = await _service.fetchMySessions(accessToken: token);
      for (final s in mySessions) {
        if (s.isLive) {
          existingLive = s;
          break;
        }
      }
    } catch (_) {
      // fall through to "create new" if the check itself fails
    }
    if (!mounted) return;
    setState(() => _checkingMyLiveSession = false);

    if (existingLive != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لديك بث مباشر قائم بالفعل — تم فتحه لك'),
      ));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LiveBroadcastScreen(sessionId: existingLive!.id)),
      );
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateLiveSessionScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hasStore = context.watch<StoreProvider>().myStore != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('البث المباشر', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: hasStore
          ? FloatingActionButton.extended(
              heroTag: 'liveSessionsGoLiveFab',
              backgroundColor: AppColors.error,
              icon: _checkingMyLiveSession
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.videocam, color: Colors.white),
              label: const Text('بثّ الآن', style: TextStyle(color: Colors.white)),
              onPressed: _checkingMyLiveSession ? null : _goLivePressed,
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: _sortOptions.map((opt) {
                  final selected = context.watch<LiveSessionsProvider>().ordering == opt.$1;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(opt.$2),
                      selected: selected,
                      selectedColor: AppColors.primaryContainer,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.onSurface,
                      ),
                      onSelected: (_) {
                        final token = auth.accessToken;
                        if (token == null) return;
                        context
                            .read<LiveSessionsProvider>()
                            .loadSessions(accessToken: token, ordering: opt.$1);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: Consumer<LiveSessionsProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.sessions.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.errorMessage != null && provider.sessions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                        const SizedBox(height: 8),
                        Text(provider.errorMessage!),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  );
                }
                if (provider.sessions.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.live_tv_outlined, size: 56, color: AppColors.onSurfaceVariant),
                        SizedBox(height: 12),
                        Text('لا توجد بثوث مباشرة الآن', style: TextStyle(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  );
                }

                final token = auth.accessToken;
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: provider.sessions.length,
                    itemBuilder: (context, index) {
                      final session = provider.sessions[index];
                      return LiveSessionCard(
                        session: session,
                        onTap: token == null
                            ? () {}
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveViewerScreen(sessionId: session.id),
                                  ),
                                ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
