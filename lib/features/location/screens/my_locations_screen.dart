import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_colors.dart';
import 'widgets/location_card_widget.dart';
import 'add_edit_location_screen.dart';

class MyLocationsScreen extends StatefulWidget {
  const MyLocationsScreen({super.key});

  @override
  State<MyLocationsScreen> createState() => _MyLocationsScreenState();
}

class _MyLocationsScreenState extends State<MyLocationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final token = context.read<AuthProvider>().accessToken;
    if (token != null) {
      context.read<LocationProvider>().loadMyLocations(token);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, int locationId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الموقع'),
        content: Text('هل تريد حذف "$name"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) return;
      final ok = await context
          .read<LocationProvider>()
          .deleteLocation(token, locationId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'تم حذف الموقع' : 'فشل الحذف'),
            backgroundColor: ok ? AppColors.success : AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _setPrimary(BuildContext context, int locationId) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final ok = await context
        .read<LocationProvider>()
        .setPrimaryLocation(token, locationId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'تم تعيين الموقع الرئيسي' : 'فشل التعيين'),
          backgroundColor: ok ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // الشاشة مدفوعة فوق MainShell (الذي يُبنى بدون Directionality صريح، أي
    // LTR افتراضيًا) — لذا نغلّف الشاشة بالكامل بـ RTL هنا صراحةً ليتطابق
    // ترتيب العناصر مع تصميم عربي سليم.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقعي'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'تحديث',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => const AddEditLocationScreen()),
          );
          if (added == true) _load();
        },
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('إضافة موقع'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer<LocationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingLocations) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.locationsError != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(provider.locationsError!,
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  OutlinedButton(
                      onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }

          if (provider.myLocations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off_rounded,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد مواقع محفوظة',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اضغط + لإضافة موقعك الأول',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: provider.myLocations.length,
              itemBuilder: (context, index) {
                final loc = provider.myLocations[index];
                return Dismissible(
                  key: ValueKey(loc.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    await _confirmDelete(context, loc.id, loc.name);
                    return false; // confirmDismiss handles its own removal
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        const Icon(Icons.delete_rounded, color: Colors.white),
                  ),
                  child: LocationCardWidget(
                    location: loc,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AddEditLocationScreen(existing: loc),
                        ),
                      ).then((_) => _load());
                    },
                    onSetPrimary: loc.isPrimary
                        ? null
                        : () => _setPrimary(context, loc.id),
                    onDelete: () =>
                        _confirmDelete(context, loc.id, loc.name),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
