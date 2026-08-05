import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import '../../models/nearby_item_model.dart';
import '../../../../theme/app_colors.dart';

// ── URL helper ───────────────────────────────────────────────────────────────
String _fixUrl(String url) =>
    url.replaceFirst('http://localhost', 'http://10.0.2.2');

// ── Triangle pin painter ──────────────────────────────────────────────────────
class _PinPainter extends CustomPainter {
  final Color color;
  const _PinPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════════════════════
// علامة منتج واحد
// ══════════════════════════════════════════════════════════════════════════════
class ItemMarkerWidget extends StatelessWidget {
  final NearbyItem item;
  final VoidCallback onTap;

  const ItemMarkerWidget({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 46;
    final imageUrl =
        item.firstImageUrl != null ? _fixUrl(item.firstImageUrl!) : null;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                  color: Colors.green.shade700, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: imageUrl != null
                  ? AppNetworkImage(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => _iconPlaceholder(),
                    )
                  : _iconPlaceholder(),
            ),
          ),
          CustomPaint(
            size: const Size(12, 7),
            painter: _PinPainter(color: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Widget _iconPlaceholder() => Container(
        color: Colors.green.shade50,
        child: Icon(Icons.sell_rounded,
            color: Colors.green.shade700, size: 22),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// علامة تجمع (cluster)
// ══════════════════════════════════════════════════════════════════════════════
class ItemClusterMarker extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const ItemClusterMarker({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sell_rounded,
                    color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(12, 7),
            painter: _PinPainter(color: Colors.green.shade700),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom sheet لمنتج واحد
// ══════════════════════════════════════════════════════════════════════════════
class ItemMarkerSheet extends StatelessWidget {
  final NearbyItem item;
  final ScrollController scrollController;
  final VoidCallback? onViewDetails;

  const ItemMarkerSheet({
    super.key,
    required this.item,
    required this.scrollController,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _DragHandle(),
          const SizedBox(height: 16),
          _ItemRow(
            item: item,
            onTap: onViewDetails ?? () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onViewDetails ?? () => Navigator.pop(context),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('عرض التفاصيل والحجز'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom sheet للتجمع (cluster sheet)
// ══════════════════════════════════════════════════════════════════════════════
class ItemClusterSheet extends StatelessWidget {
  final List<NearbyItem> items;
  final ScrollController scrollController;
  final void Function(NearbyItem) onViewDetails;

  const ItemClusterSheet({
    super.key,
    required this.items,
    required this.scrollController,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _DragHandle(),
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell_rounded,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        '${items.length} منتجات',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'في هذه المنطقة',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── List ───────────────────────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _ItemRow(
                item: items[i],
                onTap: () => onViewDetails(items[i]),
                showArrow: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// صف منتج مشترك بين الـ sheets
// ══════════════════════════════════════════════════════════════════════════════
class _ItemRow extends StatelessWidget {
  final NearbyItem item;
  final VoidCallback onTap;
  final bool showArrow;

  const _ItemRow({
    required this.item,
    required this.onTap,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        item.firstImageUrl != null ? _fixUrl(item.firstImageUrl!) : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            // ── صورة ──────────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: imageUrl != null
                    ? AppNetworkImage(imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, s) => _imgPlaceholder())
                    : _imgPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),
            // ── معلومات ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ConditionBadge(item.condition, item.conditionLabel),
                      const SizedBox(width: 8),
                      const Icon(Icons.location_on_rounded,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 3),
                      Text(
                        item.distanceText,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (item.category != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.category!.name,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (showArrow)
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: Colors.green.shade50,
        child: Center(
          child: Icon(Icons.sell_rounded,
              color: Colors.green.shade300, size: 28),
        ),
      );
}

// ── Condition badge ───────────────────────────────────────────────────────────
class _ConditionBadge extends StatelessWidget {
  final String condition;
  final String label;
  const _ConditionBadge(this.condition, this.label);

  Color get _color {
    switch (condition) {
      case 'new': return Colors.green.shade700;
      case 'like_new': return Colors.teal.shade700;
      case 'good': return Colors.blue.shade700;
      case 'fair': return Colors.orange.shade700;
      default: return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: _color, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Drag handle ───────────────────────────────────────────────────────────────
class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
