import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Shared Liquid Glass surface for the app's chrome (bars, panels, dialogs).
///
/// Wraps the package's [GlassContainer] in standalone mode (`useOwnLayer`) so
/// each surface manages its own frosted backdrop — it blurs and refracts
/// whatever is rendered behind it. Tuned per [Brightness] so the glass reads
/// over both dark photos and light gallery backgrounds.
///
/// IMPORTANT: only for chrome. Never wrap individual grid tiles — a blur per
/// tile across thousands of photos would be far too GPU-heavy.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 20,
    this.blur = 14,
    this.thickness = 16,
    this.alignment,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final double thickness;
  final AlignmentGeometry? alignment;

  /// Optional glass tint override; defaults to a subtle brightness-aware tint.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassContainer(
      useOwnLayer: true,
      padding: padding,
      margin: margin,
      alignment: alignment,
      clipBehavior: Clip.antiAlias,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      settings: LiquidGlassSettings(
        blur: blur,
        thickness: thickness,
        glassColor: tint ??
            Colors.white.withValues(alpha: dark ? 0.05 : 0.16),
      ),
      child: child,
    );
  }
}
