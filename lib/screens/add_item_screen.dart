import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/category.dart';
import '../providers/auth_provider.dart';
import '../services/category_service.dart';
import '../services/item_service.dart';
import 'dart:typed_data';
import 'create_listing_screen.dart';
import '../features/location/models/location_model.dart';
import '../features/location/providers/location_provider.dart';
import '../features/location/screens/add_edit_location_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/product/variant_builder.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _warrantyDaysController = TextEditingController(text: '7');

  String _condition = 'new';
  String _packageSize = 'medium';
  final List<XFile> _images = [];

  // Options (colour, size…). When on, stock is entered per combination and
  // the plain quantity field is replaced — the server derives the total.
  bool _hasOptions = false;
  final _variantDraft = VariantDraft();
  bool _isLoading = false;
  String? _errorMessage;

  // Category
  final _categoryService = CategoryService();
  List<Category> _rootCategories = [];
  List<Category> _subCategories = [];
  bool _loadingRoots = true;
  bool _loadingSubs = false;
  int? _selectedRootId;
  int? _selectedSubId;

  int? get _selectedCategoryId => _selectedSubId ?? _selectedRootId;

  // Location
  int? _selectedLocationId;
  String? _selectedLocationAddress;

  // أربع بدل خمس. «جيد/مقبول/ضعيف» كانت تطلب من البائع حكماً بدقة لا
  // يملكها ولا يستطيع المشتري التحقق منه — والفرق بينها رأي لا وصف.
  // و«غير معلوم» يعترف بالحالة الشائعة: بضاعة جملة لم تُفحص قطعة قطعة.
  static const _conditions = [
    {'value': 'new', 'label': 'جديد'},
    {'value': 'like_new', 'label': 'شبه جديد'},
    {'value': 'used', 'label': 'مستعمل'},
    {'value': 'unknown', 'label': 'غير معلوم'},
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRootCategories();
      _ensurePickupLocation();
    });
  }

  /// يمنع البدء بلا موقع رئيسي. الخادم يرفض الإنشاء في هذه الحالة
  /// (code: no_pickup_location) لأن شركة التوصيل تستلم من هذا العنوان،
  /// لكن رفضه بعد ملء النموذج كله وإرفاق الصور تجربة سيئة — فالفحص هنا
  /// قبل أن يكتب البائع حرفاً واحداً.
  Future<void> _ensurePickupLocation() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    final provider = context.read<LocationProvider>();
    await provider.loadMyLocations(token);
    if (!mounted || provider.myLocations.isNotEmpty) return;

    final addNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('أضف موقعك أولاً'),
        content: const Text(
          'شركة التوصيل تستلم منتجاتك من موقعك الرئيسي، فلا يمكن نشر منتج قبل تحديده.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('أضف الموقع'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (addNow != true) {
      // "لاحقاً" يعني مغادرة الشاشة لا تجاهل الشرط: البقاء فيها ينتهي
      // برفض من الخادم بعد كل هذا العمل.
      Navigator.pop(context);
      return;
    }

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditLocationScreen()),
    );
    if (!mounted) return;
    await provider.loadMyLocations(token);
    if (!mounted) return;
    if (provider.myLocations.isEmpty) {
      // لم يُحفظ شيء — لا نحبسه في حلقة حوارات.
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _warrantyDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadRootCategories() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() => _loadingRoots = true);
    try {
      final roots = await _categoryService.fetchRootCategories(
        accessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _rootCategories = roots;
        _loadingRoots = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoots = false);
    }
  }

  Future<void> _onRootSelected(Category cat) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    // منطق الرقائق السابق كان يُلغي الاختيار عند إعادة الضغط عليه —
    // سلوك صحيح لرقيقة تُضغط، وخطأ لمنسدلة: من يفتحها ويعيد اختيار نفس
    // القيمة يؤكّدها، لا يمسحها.
    if (_selectedRootId == cat.id) return;
    setState(() {
      _selectedRootId = cat.id;
      _selectedSubId = null;
      _subCategories = [];
      _loadingSubs = true;
    });
    try {
      final subs = await _categoryService.fetchSubCategories(
        accessToken: token,
        parentId: cat.id,
      );
      if (!mounted) return;
      setState(() {
        _subCategories = subs;
        _loadingSubs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  void _onSubSelected(Category cat) {
    setState(() => _selectedSubId = cat.id);
  }

  Widget _buildCategorySelector() {
    if (_loadingRoots) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // قائمتان منسدلتان بدل رقائق (chips). الفئات عندك تقارب التسعين،
    // والرقائق تمدّ النموذج شاشتين وتجعل الفئة المختارة تضيع بين
    // أخواتها — بينما المنسدلة تُظهر الاختيار دائماً في سطر واحد.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _selectedRootId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'الفئة الرئيسية',
            border: OutlineInputBorder(),
          ),
          validator: (v) => v == null ? 'اختر الفئة' : null,
          items: _rootCategories
              .map((cat) => DropdownMenuItem(
                    value: cat.id,
                    child: Text(cat.displayName,
                        textDirection: TextDirection.rtl,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            final cat = _rootCategories.firstWhere((c) => c.id == id);
            _onRootSelected(cat);
          },
        ),

        // الفرعية تظهر بعد اختيار الرئيسية فقط — وتغيب إن لم يكن للفئة
        // فروع، فلا يبقى حقل فارغ يوحي بأن شيئاً ينقص.
        if (_loadingSubs)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_selectedRootId != null && _subCategories.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedSubId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'الفئة الفرعية',
              border: OutlineInputBorder(),
            ),
            items: _subCategories
                .map((cat) => DropdownMenuItem(
                      value: cat.id,
                      child: Text(cat.displayName,
                          textDirection: TextDirection.rtl,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              final cat = _subCategories.firstWhere((c) => c.id == id);
              _onSubSelected(cat);
            },
          ),
        ],
      ],
    );
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
      builder: (_) => _ItemLocationSheet(token: token),
    );

    if (loc != null && mounted) {
      setState(() {
        _selectedLocationId = loc.id;
        _selectedLocationAddress =
            loc.fullAddress.isNotEmpty ? loc.fullAddress : loc.addressLine1;
      });
    }
  }

  /// الاستوديو أو الكاميرا.
  ///
  /// التقاط الصورة لحظة النشر هو الحالة الشائعة لبائع يصوّر بضاعته أمامه،
  /// وإجباره على التصوير ثم الخروج إلى الاستوديو خطوتان زائدتان في كل مرة.
  Future<void> _pickImages() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من الاستوديو'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      // الكاميرا تُرجع صورة واحدة لكل التقاطة — لا مقابل لـ pickMultiImage.
      final shot = await picker.pickImage(source: ImageSource.camera);
      if (shot == null) return;
      setState(() => _images.add(shot));
      return;
    }

    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _images.addAll(picked));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      setState(() => _errorMessage = 'يرجى اختيار صورة واحدة على الأقل');
      return;
    }
    if (_selectedCategoryId == null) {
      setState(() => _errorMessage = 'يرجى اختيار فئة للمنتج');
      return;
    }
    if (_hasOptions) {
      final problem = _variantDraft.validate();
      if (problem != null) {
        setState(() => _errorMessage = problem);
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final service = ItemService();

      final itemId = await service.createItem(
        accessToken: auth.accessToken!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: _selectedCategoryId!,
        condition: _condition,
        quantity: _hasOptions
            ? _variantDraft.totalQuantity
            : int.parse(_quantityController.text),
        images: _images,
        packageSize: _packageSize,
        warrantyDays: int.parse(_warrantyDaysController.text),
        locationId: _selectedLocationId,
        options: _hasOptions ? _variantDraft.optionsJson() : null,
        variants: _hasOptions ? _variantDraft.variantsJson() : null,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CreateListingScreen(
            itemId: itemId,
            itemTitle: _titleController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة منتج'),
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
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'اسم المنتج مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'الوصف',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الوصف مطلوب' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'الفئة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildCategorySelector(),
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
                textAlign: TextAlign.right,
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'هل للمنتج خيارات؟',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'لون، مقاس، سعة… يختار المشتري منها قبل الحجز',
                  style: TextStyle(fontSize: 12),
                ),
                value: _hasOptions,
                onChanged: (v) => setState(() => _hasOptions = v),
              ),
              // فاصل صريح: المفتاح أعلاه والحقل أسفله كانا متلاصقين،
              // فيبدو حقل الكمية تابعاً للسؤال لا بديلاً عنه.
              const SizedBox(height: 12),
              if (_hasOptions)
                VariantBuilder(
                  draft: _variantDraft,
                  onChanged: () => setState(() {}),
                )
              else
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
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
              const SizedBox(height: 24),
              const Text(
                'الصور',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_images.isNotEmpty)
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Stack(
                          children: [
                            FutureBuilder<List<int>>(
                              future: _images[i].readAsBytes(),
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
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _images.removeAt(i)),
                                child: Container(
                                  color: Colors.red,
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.image),
                label: const Text('اختيار صور'),
              ),
              // ── موقع المنتج ─────────────────────────────────────────
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
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('رفع المنتج'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemLocationSheet extends StatelessWidget {
  final String token;

  const _ItemLocationSheet({required this.token});

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
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'اختر موقع المنتج',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addNew(context),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                    label: const Text('إضافة جديد'),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final loc = provider.myLocations[i];
                      return ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
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
          const Icon(Icons.location_off_outlined, size: 52, color: Colors.grey),
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
