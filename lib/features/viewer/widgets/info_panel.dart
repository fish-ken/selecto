import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../photo_metadata.dart';

/// Right-hand info panel for the loupe view: an RGB histogram on top and a
/// list of EXIF fields below. Loads its data for [path] once (key it by path
/// in the parent so a new photo reloads).
class InfoPanel extends ConsumerStatefulWidget {
  const InfoPanel({
    super.key,
    required this.imagePath,
    required this.exifPath,
    required this.fileBytes,
  });

  /// The decodable file (plain JPEG, or a RAW's embedded preview) — used for
  /// the histogram and as the EXIF fallback.
  final String imagePath;

  /// The original file (e.g. a `.ARW`) — read first for EXIF, since a RAW's
  /// embedded preview often lacks an EXIF segment.
  final String exifPath;

  /// Original file size, shown as a row.
  final int fileBytes;

  @override
  ConsumerState<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends ConsumerState<InfoPanel> {
  late final Future<PhotoMetadata> _future = loadPhotoMetadata(
    widget.imagePath,
    exifPath: widget.exifPath,
    fileBytes: widget.fileBytes,
  );

  static const _bg = Color(0xFF161616);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);

    return Container(
      width: 300,
      color: _bg,
      child: FutureBuilder<PhotoMetadata>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final meta = snap.data;
          if (meta == null) {
            return _centeredHint(t.tr('exifNone'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _sectionLabel(t.tr('histogram')),
              const SizedBox(height: 8),
              _HistogramView(meta.histogram),
              const SizedBox(height: 20),
              if (meta.exif.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    t.tr('exifNone'),
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              else
                for (final row in meta.exif)
                  _ExifRowView(label: t.tr(row.labelKey), value: row.value),
            ],
          );
        },
      ),
    );
  }

  Widget _centeredHint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

class _ExifRowView extends StatelessWidget {
  const _ExifRowView({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the three channel curves over a dark plot area.
class _HistogramView extends StatelessWidget {
  const _HistogramView(this.histogram);

  final Histogram histogram;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: histogram.isEmpty
          ? const SizedBox.expand()
          : CustomPaint(
              size: Size.infinite,
              painter: _HistogramPainter(histogram),
            ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.h);

  final Histogram h;

  // Photographic RGB channels; screen blending sums them toward white where
  // they overlap, the way a histogram is conventionally shown.
  static const _red = Color(0xFFFF453A);
  static const _green = Color(0xFF32D74B);
  static const _blue = Color(0xFF0A84FF);

  @override
  void paint(Canvas canvas, Size size) {
    _drawChannel(canvas, size, h.r, _red);
    _drawChannel(canvas, size, h.g, _green);
    _drawChannel(canvas, size, h.b, _blue);
  }

  void _drawChannel(Canvas canvas, Size size, List<int> bins, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.screen
      ..color = color.withValues(alpha: 0.75);
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < 256; i++) {
      final x = i / 255 * size.width;
      final v = (bins[i] / h.max).clamp(0.0, 1.0);
      path.lineTo(x, size.height - v * size.height);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HistogramPainter old) => old.h != h;
}
