import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import '../../models/nearby_store_model.dart';
import '../../../../theme/app_colors.dart';

class StoreMarkerWidget extends StatelessWidget {
  final NearbyStore store;
  final VoidCallback onTap;

  const StoreMarkerWidget({
    super.key,
    required this.store,
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.store_rounded, color: Colors.white, size: 20),
          ),
          CustomPaint(
            size: const Size(12, 6),
            painter: _TrianglePainter(color: Colors.orange.shade700),
          ),
        ],
      ),
    );
  }
}

/// Bottom-pointing triangle for map pin tail
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// Bottom sheet content for a tapped store marker
class StoreMarkerSheet extends StatelessWidget {
  final NearbyStore store;
  final ScrollController scrollController;
  final VoidCallback? onVisit;

  const StoreMarkerSheet({
    super.key,
    required this.store,
    required this.scrollController,
    this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: store.fullLogoUrl != null
                    ? AppNetworkImage(
                        store.fullLogoUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholderLogo(),
                      )
                    : _placeholderLogo(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Text(
                          store.distanceText,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.inventory_2_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(
                          '${store.totalActiveItems} منتج',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                    if (store.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        store.description,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onVisit ?? () => Navigator.pop(context),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('زيارة المتجر'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderLogo() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.store_rounded,
          color: Colors.orange.shade400, size: 30),
    );
  }
}
