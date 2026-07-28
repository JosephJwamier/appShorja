import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/auction.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';

class EditAuctionScreen extends StatefulWidget {
  final Auction auction;

  const EditAuctionScreen({super.key, required this.auction});

  @override
  State<EditAuctionScreen> createState() => _EditAuctionScreenState();
}

class _EditAuctionScreenState extends State<EditAuctionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _startingPriceController;
  late final TextEditingController _incrementController;
  late final TextEditingController _bidDepositController;
  late DateTime _startTime;
  late DateTime _endTime;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final a = widget.auction;
    _startingPriceController =
        TextEditingController(text: a.startingPrice.toStringAsFixed(0));
    _incrementController =
        TextEditingController(text: a.minimumIncrement.toStringAsFixed(0));
    _bidDepositController =
        TextEditingController(text: a.bidDeposit.toStringAsFixed(0));
    _startTime = a.startTime;
    _endTime = a.endTime;
  }

  @override
  void dispose() {
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

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_endTime.isAfter(_startTime)) {
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

      await service.updateAuction(
        accessToken: auth.accessToken!,
        itemId: widget.auction.item.id,
        auctionId: widget.auction.id,
        startingPrice: double.parse(_startingPriceController.text),
        minimumIncrement: double.parse(_incrementController.text),
        bidDeposit: double.parse(_bidDepositController.text),
        startTime: _startTime,
        endTime: _endTime,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ تعديلات المزاد'),
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
          title: const Text('تعديل المزاد'),
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
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gavel_outlined, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تعديل مزاد "${widget.auction.item.title}"',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _startingPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'السعر الافتتاحي (\$)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'السعر الافتتاحي مطلوب';
                    }
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
                    labelText: 'الحدّ الأدنى للزيادة (\$)',
                    border: OutlineInputBorder(),
                    helperText: 'الفارق المطلوب بين كلّ مزايدة وما قبلها',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'الحدّ الأدنى مطلوب';
                    }
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
                    labelText: 'عربون المزايدة (\$)',
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
                        leading: const Icon(Icons.event_available,
                            color: Colors.green),
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
                        leading:
                            const Icon(Icons.event_busy, color: Colors.red),
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
