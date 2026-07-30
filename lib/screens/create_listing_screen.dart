import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/items_provider.dart';
import '../providers/auctions_provider.dart';
import '../services/item_service.dart';

class CreateListingScreen extends StatefulWidget {
  final int itemId;
  final String itemTitle;

  const CreateListingScreen({
    super.key,
    required this.itemId,
    required this.itemTitle,
  });

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isAuction = false;

  // حقول السعر الثابت
  final _priceController = TextEditingController();
  final _depositController = TextEditingController(text: '10');

  // حقول المزاد
  final _startingPriceController = TextEditingController();
  final _incrementController = TextEditingController();
  final _bidDepositController = TextEditingController();
  late DateTime _startTime;
  late DateTime _endTime;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startTime = now.add(const Duration(hours: 1));
    _endTime = now.add(const Duration(days: 1, hours: 1));
  }

  @override
  void dispose() {
    _priceController.dispose();
    _depositController.dispose();
    _startingPriceController.dispose();
    _incrementController.dispose();
    _bidDepositController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final day = dt.day;
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'م' : 'ص';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$day $month $year • $displayHour:$minute $ampm';
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isAuction && !_endTime.isAfter(_startTime)) {
      setState(() => _errorMessage = 'وقت النهاية يجب أن يكون بعد وقت البداية');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final service = ItemService();

      if (_isAuction) {
        await service.createAuction(
          accessToken: auth.accessToken!,
          itemId: widget.itemId,
          startingPrice: double.parse(_startingPriceController.text),
          minimumIncrement: double.parse(_incrementController.text),
          bidDeposit: double.parse(_bidDepositController.text),
          startTime: _startTime,
          endTime: _endTime,
        );
      } else {
        await service.createFixedListing(
          accessToken: auth.accessToken!,
          itemId: widget.itemId,
          price: double.parse(_priceController.text),
          depositPercentage: double.parse(_depositController.text),
        );
      }

      if (!mounted) return;

      // تحديث المكان المركزي المناسب
      if (_isAuction) {
        await Provider.of<AuctionsProvider>(context, listen: false)
            .loadAuctions(accessToken: auth.accessToken!);
      } else {
        await Provider.of<ItemsProvider>(context, listen: false)
            .loadListings(accessToken: auth.accessToken!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAuction ? 'تم إنشاء المزاد بنجاح' : 'تم نشر المنتج بنجاح',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
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
        title: const Text('نشر للبيع'),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم رفع "${widget.itemTitle}" كمسوّدة. اختر طريقة النشر.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('سعر ثابت'),
                      icon: Icon(Icons.attach_money),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('مزاد'),
                      icon: Icon(Icons.gavel),
                    ),
                  ],
                  selected: {_isAuction},
                  onSelectionChanged: (Set<bool> selection) {
                    setState(() {
                      _isAuction = selection.first;
                      _errorMessage = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
              if (_isAuction) ..._buildAuctionFields() else ..._buildFixedFields(),
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
                      : Text(_isAuction ? 'إنشاء المزاد' : 'نشر للبيع'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                child: const Text('إبقاؤه كمسوّدة الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFixedFields() {
    return [
      TextFormField(
        controller: _priceController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'السعر (IQD)',
          border: OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'السعر مطلوب';
          final n = double.tryParse(v);
          if (n == null || n <= 0) return 'يجب أن يكون رقماً موجباً';
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _depositController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'نسبة العربون (٪)',
          border: OutlineInputBorder(),
          helperText:
              'النسبة المطلوبة كعربون لحجز المنتج — ضع 0 لعدم أخذ أي عربون (الدفع بالكامل كاش عند التوصيل)',
          helperMaxLines: 2,
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'النسبة مطلوبة';
          final n = double.tryParse(v);
          if (n == null || n < 0 || n > 100) return 'النسبة بين 0 و 100';
          return null;
        },
      ),
    ];
  }

  List<Widget> _buildAuctionFields() {
    return [
      TextFormField(
        controller: _startingPriceController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'السعر الافتتاحي (IQD)',
          border: OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'السعر الافتتاحي مطلوب';
          final n = double.tryParse(v);
          if (n == null || n <= 0) return 'يجب أن يكون رقماً موجباً';
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _incrementController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'الحدّ الأدنى للزيادة (IQD)',
          border: OutlineInputBorder(),
          helperText: 'الفارق المطلوب بين كلّ مزايدة وما قبلها',
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'الحدّ الأدنى مطلوب';
          final n = double.tryParse(v);
          if (n == null || n <= 0) return 'يجب أن يكون رقماً موجباً';
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _bidDepositController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'عربون المزايدة (IQD)',
          border: OutlineInputBorder(),
          helperText: 'مبلغ يُجمَّد من كلّ مزايد لجدّيّة العرض',
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'العربون مطلوب';
          final n = double.tryParse(v);
          if (n == null || n < 0) return 'يجب أن يكون رقماً غير سالب';
          return null;
        },
      ),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.event_available, color: Colors.green),
              title: const Text('وقت البداية'),
              subtitle: Text(_formatDateTime(_startTime)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await _pickDateTime(_startTime);
                if (picked != null) setState(() => _startTime = picked);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.event_busy, color: Colors.red),
              title: const Text('وقت النهاية'),
              subtitle: Text(_formatDateTime(_endTime)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await _pickDateTime(_endTime);
                if (picked != null) setState(() => _endTime = picked);
              },
            ),
          ],
        ),
      ),
    ];
  }
}