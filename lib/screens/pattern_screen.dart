import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Reusable 9-dot pattern widget. Dots are numbered 0..8 in a 3x3 grid:
///   0 1 2
///   3 4 5
///   6 7 8
///
/// [onComplete] is called with the sequence of visited dot indices when the
/// user lifts their finger.
class PatternPad extends StatefulWidget {
  const PatternPad({
    super.key,
    required this.onComplete,
    this.highlightColor = const Color(0xFF00B8A9),
    this.errorFlash = false,
    this.disabled = false,
  });

  final void Function(List<int> dots) onComplete;
  final Color highlightColor;
  final bool errorFlash;
  final bool disabled;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> _selected = [];
  Offset? _currentPointer;
  final GlobalKey _padKey = GlobalKey();
  final double _dotRadius = 14;
  final double _hitRadius = 40;

  List<Offset> _dotCenters(Size size) {
    final cellW = size.width / 3;
    final cellH = size.height / 3;
    return List.generate(9, (i) {
      final col = i % 3;
      final row = i ~/ 3;
      return Offset(cellW * (col + 0.5), cellH * (row + 0.5));
    });
  }

  int? _hitDot(Offset pos, Size size) {
    final centers = _dotCenters(size);
    for (var i = 0; i < centers.length; i++) {
      if ((centers[i] - pos).distance <= _hitRadius) return i;
    }
    return null;
  }

  void _reset() {
    setState(() {
      _selected.clear();
      _currentPointer = null;
    });
  }

  @override
  void didUpdateWidget(covariant PatternPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorFlash && !oldWidget.errorFlash) {
      // Briefly show red then clear.
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _reset();
      });
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (widget.disabled) return;
    final size = (_padKey.currentContext!.findRenderObject() as RenderBox).size;
    final local = d.localPosition;
    final hit = _hitDot(local, size);
    setState(() {
      _selected.clear();
      _currentPointer = local;
      if (hit != null) _selected.add(hit);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (widget.disabled) return;
    final size = (_padKey.currentContext!.findRenderObject() as RenderBox).size;
    final local = d.localPosition;
    final hit = _hitDot(local, size);
    setState(() {
      _currentPointer = local;
      if (hit != null && !_selected.contains(hit)) {
        _selected.add(hit);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (widget.disabled) return;
    if (_selected.isEmpty) return;
    final snapshot = List<int>.from(_selected);
    setState(() {
      _currentPointer = null;
      _selected.clear();
    });
    widget.onComplete(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.errorFlash ? Colors.redAccent : widget.highlightColor;
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          key: _padKey,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return CustomPaint(
                painter: _PatternPainter(
                  selected: _selected,
                  pointer: _currentPointer,
                  centers: _dotCenters(size),
                  color: color,
                  dotRadius: _dotRadius,
                  baseColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.25),
                ),
                size: size,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.selected,
    required this.pointer,
    required this.centers,
    required this.color,
    required this.dotRadius,
    required this.baseColor,
  });

  final List<int> selected;
  final Offset? pointer;
  final List<Offset> centers;
  final Color color;
  final double dotRadius;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()..color = baseColor;
    final activePaint = Paint()..color = color;
    final linePaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Lines first
    for (var i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(centers[selected[i]], centers[selected[i + 1]], linePaint);
    }
    if (selected.isNotEmpty && pointer != null) {
      canvas.drawLine(centers[selected.last], pointer!, linePaint);
    }

    // Dots
    for (var i = 0; i < centers.length; i++) {
      final active = selected.contains(i);
      canvas.drawCircle(centers[i], dotRadius, active ? activePaint : basePaint);
      if (active) {
        canvas.drawCircle(
          centers[i],
          dotRadius + 8,
          Paint()
            ..color = color.withOpacity(0.2)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.selected != selected ||
      old.pointer != pointer ||
      old.color != color;
}

/// Full-screen pattern setup screen: asks the user to draw the pattern twice
/// and persists it via [onConfirm].
class PatternSetupScreen extends StatefulWidget {
  const PatternSetupScreen({
    super.key,
    required this.onConfirm,
  });

  final Future<void> Function(List<int> dots) onConfirm;

  @override
  State<PatternSetupScreen> createState() => _PatternSetupScreenState();
}

class _PatternSetupScreenState extends State<PatternSetupScreen> {
  List<int>? _firstDraw;
  String? _message;
  bool _error = false;
  bool _busy = false;

  void _handle(List<int> dots) async {
    final l = AppLocalizations.of(context);
    if (dots.length < 4) {
      setState(() {
        _message = l.get('pattern_too_short');
        _error = true;
      });
      return;
    }
    if (_firstDraw == null) {
      setState(() {
        _firstDraw = dots;
        _message = l.get('pattern_confirm');
        _error = false;
      });
    } else {
      if (_listEq(_firstDraw!, dots)) {
        setState(() => _busy = true);
        try {
          await widget.onConfirm(dots);
          if (mounted) Navigator.of(context).pop(true);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      } else {
        setState(() {
          _firstDraw = null;
          _message = l.get('pattern_mismatch');
          _error = true;
        });
      }
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.get('pattern_setup_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                _firstDraw == null
                    ? l.get('pattern_draw_new')
                    : l.get('pattern_confirm'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _error ? Colors.redAccent : const Color(0xFF00B8A9),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: PatternPad(
                      errorFlash: _error,
                      disabled: _busy,
                      onComplete: _handle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
