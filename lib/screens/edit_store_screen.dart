import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../features/location/models/location_model.dart';
import '../features/location/providers/location_provider.dart';
import '../features/location/screens/add_edit_location_screen.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../providers/store_provider.dart';
import '../theme/app_colors.dart';

class EditStoreScreen extends StatefulWidget {
  final Store store;
  const EditStoreScreen({super.key, required this.store});

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _phoneController;
  late final TextEditingController _whatsappController;
  XFile? _newLogo;
  XFile? _newCover;
  late bool _isActive;
  String? _errorMessage;

  int? _selectedLocationId;
  String? _selectedLocationAddress;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.store.name);
    _descriptionController =
        TextEditingController(text: widget.store.description);
    _phoneController = TextEditingController(text: widget.store.phoneNumber);
    _whatsappController =
        TextEditingController(text: widget.store.whatsappNumber);
    _isActive = widget.store.isActive;
    _selectedLocationId = widget.store.defaultLocationId;
    _selectedLocationAddress = widget.store.defaultLocation;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newLogo = picked);
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newCover = picked);
    }
  }

  Future<void> _pickLocation() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    await context.read<LocationProvider>().loadMyLocations(token);
    if (!mounted) return;

    final loc = await showModalBottomSheet<LocationModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StoreLocationSheet(token: token),
    );

    if (loc != null && mounted) {
      setState(() {
        _selectedLocationId = loc.id;
        _selectedLocationAddress =
            loc.fullAddress.isNotEmpty ? loc.fullAddress : loc.addressLine1;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final storeProvider = Provider.of<StoreProvider>(context, listen: false);

    final result = await storeProvider.updateStore(
      accessToken: auth.accessToken!,
      storeId: widget.store.id,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      isActive: _isActive,
      logo: _newLogo,
      cover: _newCover,
      locationId: _selectedLocationId,
      phoneNumber: _phoneController.text.trim(),
      whatsappNumber: _whatsappController.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, storeProvider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('تعديل المتجر'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── صورة الغلاف ───────────────────────────────────────
                  GestureDetector(
                    onTap: storeProvider.isUpdating ? null : _pickCover,
                    child: Container(
                      height: 130,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[200],
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _coverWidget(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'اضغط لتغيير صورة الغلاف',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ── الشعار ────────────────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: storeProvider.isUpdating ? null : _pickLogo,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: ClipOval(child: _logoWidget()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'اضغط لتغيير الشعار',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── الاسم ─────────────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المتجر',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'الاسم مطلوب';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // ── الوصف ─────────────────────────────────────────────
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'وصف المتجر',
                      hintText: 'ماذا تبيع؟ ما الذي يميّز متجرك؟',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'الوصف مطلوب';
                      }
                      return null;
                    },
                  ),
                  // ── معلومات التواصل ───────────────────────────────────
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم هاتف المتجر (اختياري)',
                      hintText: '07xxxxxxxxx',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _whatsappController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم واتساب المتجر (اختياري)',
                      hintText: '07xxxxxxxxx',
                      prefixIcon: Icon(Icons.chat_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  // ── موقع المتجر ───────────────────────────────────────
                  const SizedBox(height: 24),
                  const Text(
                    'موقع المتجر (اختياري)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: storeProvider.isUpdating ? null : _pickLocation,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _selectedLocationId != null
                              ? AppColors.primary
                              : AppColors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: _selectedLocationId != null
                            ? AppColors.primaryFixed
                            : AppColors.surfaceContainerLowest,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedLocationId != null
                                ? Icons.location_on_rounded
                                : Icons.add_location_alt_outlined,
                            color: _selectedLocationId != null
                                ? AppColors.primary
                                : Colors.grey,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _selectedLocationAddress ??
                                  'اضغط لاختيار موقع من مواقعك المحفوظة',
                              style: TextStyle(
                                color: _selectedLocationAddress != null
                                    ? AppColors.onSurface
                                    : Colors.grey[600],
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedLocationId != null)
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: AppColors.error),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => setState(() {
                                _selectedLocationId = null;
                                _selectedLocationAddress = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // ── حالة المتجر ───────────────────────────────────────
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: storeProvider.isUpdating
                        ? null
                        : (v) => setState(() => _isActive = v),
                    title: const Text('المتجر نشط'),
                    subtitle: Text(_isActive
                        ? 'المتجر مرئي للمستخدمين'
                        : 'المتجر مخفي عن المستخدمين'),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed:
                          storeProvider.isUpdating ? null : _submit,
                      icon: storeProvider.isUpdating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(storeProvider.isUpdating
                          ? 'جاري الحفظ...'
                          : 'حفظ التغييرات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _logoWidget() {
    if (_newLogo != null) {
      return Image.file(File(_newLogo!.path), fit: BoxFit.cover);
    }
    if (widget.store.fullLogoUrl != null) {
      return Image.network(
        widget.store.fullLogoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _logoFallback(),
      );
    }
    return _logoFallback();
  }

  Widget _logoFallback() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.add_a_photo_outlined,
          size: 40, color: Colors.grey),
    );
  }

  Widget _coverWidget() {
    if (_newCover != null) {
      return Image.file(File(_newCover!.path),
          fit: BoxFit.cover, width: double.infinity);
    }
    final url = widget.store.fullCoverUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _coverFallback(),
      );
    }
    return _coverFallback();
  }

  Widget _coverFallback() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 32, color: Colors.grey),
          SizedBox(height: 4),
          Text('صورة الغلاف',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StoreLocationSheet extends StatelessWidget {
  final String token;

  const _StoreLocationSheet({required this.token});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'اختر موقع المتجر',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addNew(context),
                    icon:
                        const Icon(Icons.add_location_alt_rounded, size: 18),
                    label: const Text('إضافة جديد'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<LocationProvider>(
                builder: (_, provider, _) {
                  if (provider.isLoadingLocations) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.myLocations.isEmpty) {
                    return _EmptyLocations(onAdd: () => _addNew(context));
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: provider.myLocations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final loc = provider.myLocations[i];
                      return ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryFixed,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_iconFor(loc.locationType),
                              color: AppColors.primary, size: 20),
                        ),
                        title: Text(loc.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          loc.fullAddress.isNotEmpty
                              ? loc.fullAddress
                              : loc.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: loc.isPrimary
                            ? const Icon(Icons.star_rounded,
                                color: AppColors.primary, size: 18)
                            : const Icon(Icons.chevron_right_rounded,
                                color: Colors.grey),
                        onTap: () => Navigator.pop(context, loc),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNew(BuildContext context) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditLocationScreen()),
    );
    if (ok == true && context.mounted) {
      final provider = context.read<LocationProvider>();
      if (provider.myLocations.isNotEmpty) {
        Navigator.pop(context, provider.myLocations.first);
      }
    }
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'user_address':
        return Icons.home_rounded;
      case 'store':
        return Icons.store_rounded;
      case 'warehouse':
        return Icons.warehouse_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }
}

class _EmptyLocations extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyLocations({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined,
              size: 52, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('لا توجد مواقع محفوظة',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('إضافة موقع جديد'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
