import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../features/location/models/location_model.dart';
import '../features/location/providers/location_provider.dart';
import '../features/location/screens/add_edit_location_screen.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/my_items_provider.dart';
import '../services/item_service.dart';
import '../theme/app_colors.dart';

class EditItemScreen extends StatefulWidget {
  final Product product;

  const EditItemScreen({super.key, required this.product});

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;
  late final TextEditingController _warrantyDaysController;

  late String _condition;
  late String _packageSize;
  int? _categoryId;
  late List<String> _existingImageUrls;
  late List<int> _existingImageIds;
  final Set<int> _removeImageIds = {};
  final List<XFile> _newImages = [];

  bool _isLoading = false;
  String? _errorMessage;

  int? _selectedLocationId;
  String? _selectedLocationAddress;

  static const _conditions = [
    {'value': 'new', 'label': 'جديد'},
    {'value': 'like_new', 'label': 'شبه جديد'},
    {'value': 'good', 'label': 'جيد'},
    {'value': 'fair', 'label': 'مقبول'},
    {'value': 'poor', 'label': 'ضعيف'},
  ];

  // يحدّد عدد المنتجات القابلة لدمجها بشحنة توصيل واحدة برسم واحد.
  static const _packageSizes = [
    {'value': 'small', 'label': 'صغير (مثل: هاتف، إكسسوار)'},
    {'value': 'medium', 'label': 'متوسط (مثل: حذاء، حقيبة)'},
    {'value': 'large', 'label': 'كبير (مثل: جهاز كهربائي صغير)'},
    {'value': 'bulky', 'label': 'ضخم (مثل: أثاث)'},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _titleController = TextEditingController(text: p.title);
    _descriptionController = TextEditingController(text: p.description);
    _quantityController = TextEditingController(text: p.quantity.toString());
    _warrantyDaysController =
        TextEditingController(text: p.warrantyDays.toString());
    _condition = _conditions.any((c) => c['value'] == p.condition)
        ? p.condition
        : 'new';
    _packageSize = _packageSizes.any((s) => s['value'] == p.packageSize)
        ? p.packageSize
        : 'medium';
    _categoryId = p.categoryId;
    _existingImageUrls = List.from(p.imageUrls);
    _existingImageIds = List.from(p.imageIds);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().accessToken;
      if (token != null) {
        context.read<CategoryProvider>().loadCategories(accessToken: token);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _warrantyDaysController.dispose();
    super.dispose();
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
      builder: (_) => _EditItemLocationSheet(token: token),
    );

    if (loc != null && mounted) {
      setState(() {
        _selectedLocationId = loc.id;
        _selectedLocationAddress =
            loc.fullAddress.isNotEmpty ? loc.fullAddress : loc.addressLine1;
      });
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _newImages.addAll(picked));
  }

  int get _remainingImageCount =>
      _existingImageUrls.length -
      _existingImageIds.where(_removeImageIds.contains).length +
      _newImages.length;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _errorMessage = 'اختر فئة للمنتج');
      return;
    }
    if (_remainingImageCount < 1) {
      setState(() => _errorMessage = 'يجب أن تبقى صورة واحدة على الأقل');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final service = ItemService();

      await service.updateItem(
        accessToken: auth.accessToken!,
        itemId: widget.product.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: _categoryId!,
        condition: _condition,
        quantity: int.parse(_quantityController.text),
        packageSize: _packageSize,
        warrantyDays: int.parse(_warrantyDaysController.text),
        locationId: _selectedLocationId,
        newImages: _newImages,
        removeImageIds: _removeImageIds.toList(),
      );

      if (!mounted) return;

      final myItems = Provider.of<MyItemsProvider>(context, listen: false);
      await myItems.loadMyItems(
        accessToken: auth.accessToken!,
        ownerId: auth.user!.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ التعديلات'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل المنتج'),
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
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'الوصف',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الوصف مطلوب' : null,
                ),
                const SizedBox(height: 16),
                Consumer<CategoryProvider>(
                  builder: (context, catProvider, _) {
                    final categories = catProvider.categories;
                    final hasSelected =
                        categories.any((c) => c.id == _categoryId);
                    return DropdownButtonFormField<int>(
                      initialValue: hasSelected ? _categoryId : null,
                      decoration: InputDecoration(
                        labelText: 'الفئة',
                        border: const OutlineInputBorder(),
                        suffixIcon: catProvider.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      items: categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _categoryId = value),
                      validator: (_) =>
                          _categoryId == null ? 'اختر فئة للمنتج' : null,
                    );
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _condition,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                  ),
                  items: _conditions
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['value']!,
                          child: Text(c['label']!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _condition = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _packageSize,
                  decoration: const InputDecoration(
                    labelText: 'حجم الطرد (لدمج التوصيل)',
                    border: OutlineInputBorder(),
                  ),
                  items: _packageSizes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['value']!,
                          child: Text(s['label']!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _packageSize = value);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _warrantyDaysController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مدة الضمان (بالأيام)',
                    helperText:
                        'المدة قبل تحرير المبلغ للبائع تلقائياً إن لم يوافق المشتري (الحد الأدنى يوم واحد)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مدة الضمان مطلوبة';
                    final n = int.tryParse(v);
                    if (n == null || n < 1) return 'يجب أن تكون رقماً صحيحاً 1 أو أكثر';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'الكمية مطلوبة';
                    final n = int.tryParse(v);
                    if (n == null || n < 1) return 'يجب أن تكون رقماً صحيحاً';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text('الصور', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _existingImageUrls.length; i++)
                        if (i >= _existingImageIds.length ||
                            !_removeImageIds.contains(_existingImageIds[i]))
                          _ImageThumb(
                            onRemove: i < _existingImageIds.length
                                ? () => setState(() =>
                                    _removeImageIds.add(_existingImageIds[i]))
                                : null,
                            child: AppNetworkImage(
                              _existingImageUrls[i],
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 100,
                                height: 100,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                      for (var i = 0; i < _newImages.length; i++)
                        _ImageThumb(
                          onRemove: () =>
                              setState(() => _newImages.removeAt(i)),
                          child: FutureBuilder<List<int>>(
                            future: _newImages[i].readAsBytes(),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.grey[300],
                                );
                              }
                              return Image.memory(
                                Uint8List.fromList(snap.data!),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.image),
                  label: const Text('إضافة صور'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'موقع المنتج (اختياري)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickLocation,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                                'اضغط لتغيير موقع المنتج',
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
                const SizedBox(height: 24),
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
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback? onRemove;

  const _ImageThumb({required this.child, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  color: Colors.red,
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditItemLocationSheet extends StatelessWidget {
  final String token;

  const _EditItemLocationSheet({required this.token});

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
                      'اختر موقع المنتج',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addNew(context),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 18),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
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
          const Icon(Icons.location_off_outlined, size: 52, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('لا توجد مواقع محفوظة',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('إضافة موقع جديد'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
