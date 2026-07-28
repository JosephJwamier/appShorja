import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/iraq_governorate.dart';
import '../models/location_model.dart';
import '../providers/location_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_colors.dart';
import 'map_picker_screen.dart';

class AddEditLocationScreen extends StatefulWidget {
  final LocationModel? existing;

  const AddEditLocationScreen({super.key, this.existing});

  @override
  State<AddEditLocationScreen> createState() => _AddEditLocationScreenState();
}

class _AddEditLocationScreenState extends State<AddEditLocationScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addr1Ctrl;
  late final TextEditingController _cityCtrl;
  String? _selectedGovernorate;
  late final TextEditingController _postalCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _contactPersonCtrl;
  late final TextEditingController _contactPhoneCtrl;

  String _locationType = 'user_address';
  bool _isPrimary = false;
  bool _isActive = true;
  LatLng? _pickedLatLng;
  bool _saving = false;
  bool _loadingGps = false;

  static const _locationTypes = [
    ('user_address', 'عنوان شخصي', Icons.home_rounded),
    ('store', 'متجر', Icons.store_rounded),
    ('warehouse', 'مستودع', Icons.warehouse_rounded),
    ('other', 'أخرى', Icons.location_on_rounded),
  ];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _addr1Ctrl = TextEditingController(text: e?.addressLine1 ?? '');
    _cityCtrl = TextEditingController(text: e?.city ?? '');
    // Older locations may hold free-text junk from before the governorate
    // list was fixed — only preselect it if it's still a valid governorate.
    _selectedGovernorate =
        e != null && iraqGovernorates.any((g) => g.name == e.state)
        ? e.state
        : null;
    _postalCtrl = TextEditingController(text: e?.postalCode ?? '');
    _countryCtrl = TextEditingController(text: e?.country ?? 'العراق');
    _contactPersonCtrl = TextEditingController(text: e?.contactPerson ?? '');
    _contactPhoneCtrl = TextEditingController(text: e?.contactPhone ?? '');
    _locationType = e?.locationType ?? 'user_address';
    _isPrimary = e?.isPrimary ?? false;
    _isActive = e?.isActive ?? true;
    if (e?.latitude != null && e?.longitude != null) {
      _pickedLatLng = LatLng(e!.latitude!, e.longitude!);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addr1Ctrl.dispose();
    _cityCtrl.dispose();
    _postalCtrl.dispose();
    _countryCtrl.dispose();
    _contactPersonCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  // ── فتح الخارطة الكاملة للاختيار ─────────────────────────────────────────
  Future<void> _pickOnMap() async {
    final result = await MapPickerScreen.pick(context, initial: _pickedLatLng);
    if (result != null && mounted) {
      setState(() => _pickedLatLng = result);
    }
  }

  // ── تحديد الموقع الحالي مباشرة ──────────────────────────────────────────
  Future<void> _getMyLocation() async {
    setState(() => _loadingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الرجاء السماح بالوصول للموقع من الإعدادات'),
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() => _pickedLatLng = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديد موقعك الحالي')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'location_type': _locationType,
      'name': _nameCtrl.text.trim(),
      'address_line1': _addr1Ctrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'state': _selectedGovernorate,
      if (_postalCtrl.text.trim().isNotEmpty)
        'postal_code': _postalCtrl.text.trim(),
      'country': _countryCtrl.text.trim(),
      'contact_person': _contactPersonCtrl.text.trim(),
      'contact_phone': _contactPhoneCtrl.text.trim(),
      if (_pickedLatLng != null)
        'latitude': _pickedLatLng!.latitude.toStringAsFixed(6),
      if (_pickedLatLng != null)
        'longitude': _pickedLatLng!.longitude.toStringAsFixed(6),
      'is_primary': _isPrimary,
      'is_active': _isActive,
    };

    final provider = context.read<LocationProvider>();
    bool ok;
    if (_isEditing) {
      ok = await provider.updateLocation(token, widget.existing!.id, data);
    } else {
      ok = await provider.createLocation(token, data);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.locationsError ?? 'فشل الحفظ'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'تعديل الموقع' : 'إضافة موقع جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'حفظ',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── نوع الموقع ─────────────────────────────────────────────────
            const Text(
              'نوع الموقع',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _locationTypes.map((t) {
                final (value, label, icon) = t;
                final selected = _locationType == value;
                return FilterChip(
                  avatar: Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : AppColors.primary,
                  ),
                  label: Text(label),
                  selected: selected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.onSurface,
                  ),
                  onSelected: (_) => setState(() => _locationType = value),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── تحديد الموقع الجغرافي ──────────────────────────────────────
            const Text(
              'الموقع الجغرافي',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),

            // بطاقة الموقع المحدد
            if (_pickedLatLng != null)
              _LocationPickedCard(
                latLng: _pickedLatLng!,
                onEdit: _pickOnMap,
                onRemove: () => setState(() => _pickedLatLng = null),
              )
            else
              _LocationPickerBtn(onTap: _pickOnMap),

            const SizedBox(height: 10),

            // زر "موقعي الحالي"
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _loadingGps ? null : _getMyLocation,
                icon: _loadingGps
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded, size: 20),
                label: Text(
                  _loadingGps ? 'جارٍ التحديد...' : 'استخدم موقعي الحالي',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── حقول العنوان ────────────────────────────────────────────────
            _field(_nameCtrl, 'اسم الموقع *', required: true),
            _field(_addr1Ctrl, 'العنوان *', required: true),
            Row(
              children: [
                Expanded(child: _field(_cityCtrl, 'المدينة *', required: true)),
                const SizedBox(width: 12),
                Expanded(child: _governorateField()),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field(_postalCtrl, 'الرمز البريدي (اختياري)')),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_countryCtrl, 'الدولة *', required: true),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),

            // ── معلومات التواصل ─────────────────────────────────────────────
            const Text(
              'معلومات التواصل',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _field(_contactPersonCtrl, 'اسم جهة التواصل *', required: true),
            _field(
              _contactPhoneCtrl,
              'رقم الهاتف *',
              required: true,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),

            // ── خيارات ─────────────────────────────────────────────────────
            SwitchListTile(
              value: _isPrimary,
              onChanged: (v) => setState(() => _isPrimary = v),
              title: const Text('موقع رئيسي'),
              subtitle: const Text('يُستخدم كعنوان افتراضي'),
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primaryContainer,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('نشط'),
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primaryContainer,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
            : null,
      ),
    );
  }

  Widget _governorateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedGovernorate,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'المحافظة *',
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        items: iraqGovernorates
            .map((g) => DropdownMenuItem(value: g.name, child: Text(g.name)))
            .toList(),
        onChanged: (v) => setState(() => _selectedGovernorate = v),
        validator: (v) => v == null ? 'اختر المحافظة' : null,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// بطاقة الموقع المحدد
// ══════════════════════════════════════════════════════════════════════════════
class _LocationPickedCard extends StatelessWidget {
  final LatLng latLng;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _LocationPickedCard({
    required this.latLng,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade400, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: Colors.green.shade700,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم تحديد الموقع',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${latLng.latitude.toStringAsFixed(5)}, '
                  '${latLng.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('تعديل'),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.error,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// زر فتح الخارطة (لما لا يوجد موقع محدد)
// ══════════════════════════════════════════════════════════════════════════════
class _LocationPickerBtn extends StatelessWidget {
  final VoidCallback onTap;

  const _LocationPickerBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primaryFixed,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            const Text(
              'حدّد الموقع على الخارطة',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
