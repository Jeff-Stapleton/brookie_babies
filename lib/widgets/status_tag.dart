import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// What a [StatusTag] or [InlineMessage] reports.
enum StatusTone { neutral, success, danger }

({Color foreground, Color background}) _toneColors(BrookieColors c, StatusTone tone) => switch (tone) {
      StatusTone.neutral => (foreground: c.inkSoft, background: c.surfaceSunk),
      StatusTone.success => (foreground: c.success, background: c.successSoft),
      StatusTone.danger => (foreground: c.danger, background: c.dangerSoft),
    };

/// A short status word on a soft fill: "Paid", "Ready to download", "Taken".
///
/// Color never carries the meaning alone; the [label] always says it.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.label, this.tone = StatusTone.neutral, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(BrookieColors.of(context), tone);
    final icon = this.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(BrookieRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BrookieSpace.s2, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.foreground),
              const SizedBox(width: BrookieSpace.s1),
            ],
            // Wraps rather than overflowing a narrow card at large text sizes.
            Flexible(
              child: Text(
                label,
                style: BrookieType.small.copyWith(color: colors.foreground, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sentence on a soft fill that reports what happened, and for errors, how
/// to fix it: "Your card was declined. Try another card, or call your bank."
class InlineMessage extends StatelessWidget {
  const InlineMessage({super.key, required this.message, this.tone = StatusTone.danger, this.icon});

  final String message;
  final StatusTone tone;

  /// Defaults to an info outline for neutral, a check for success and an
  /// error outline for danger.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(BrookieColors.of(context), tone);
    final icon = this.icon ??
        switch (tone) {
          StatusTone.neutral => Icons.info_outline,
          StatusTone.success => Icons.check,
          StatusTone.danger => Icons.error_outline,
        };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(BrookieRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BrookieSpace.s4, vertical: BrookieSpace.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: colors.foreground),
              ),
              const SizedBox(width: BrookieSpace.s2),
              Expanded(child: Text(message, style: BrookieType.ui.copyWith(color: colors.foreground))),
            ],
          ),
        ),
      ),
    );
  }
}
