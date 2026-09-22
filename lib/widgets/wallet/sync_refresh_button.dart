import 'package:flutter/material.dart';

/// The circular arrow: spins while the wallet re-syncs unfinished top-ups and
/// reloads everything. Ignores taps while already running so two presses
/// cannot fire two syncs.
class SyncRefreshButton extends StatefulWidget {
  final bool busy;
  final Future<void> Function() onPressed;
  final String tooltip;

  const SyncRefreshButton({
    super.key,
    required this.busy,
    required this.onPressed,
    this.tooltip = 'تحديث ومزامنة العمليات المعلّقة',
  });

  @override
  State<SyncRefreshButton> createState() => _SyncRefreshButtonState();
}

class _SyncRefreshButtonState extends State<SyncRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(SyncRefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      // Finish the current turn so the arrow never freezes mid-rotation.
      _spin.forward(from: _spin.value).whenComplete(() {
        if (mounted) _spin.reset();
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.busy ? null : widget.onPressed,
      icon: RotationTransition(
        turns: _spin,
        child: const Icon(Icons.sync),
      ),
    );
  }
}
