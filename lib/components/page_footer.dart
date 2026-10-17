import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:flutter/material.dart';

/// The page's quiet sign-off on paper: the logo, the studio's name and the
/// copyright.
class PageFooter extends StatelessWidget {
  const PageFooter({super.key});

  static const _logoWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.paper, border: Border(top: BorderSide(color: c.line))),
      child: ContentWidth(
        child: Padding(
          // The logo keeps clear space of at least a quarter of its disc
          // (about 18px here) on every side.
          padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s6),
          child: Row(
            children: [
              // Used exactly as supplied: never recolored, cropped or redrawn.
              Image.asset('assets/logo.png', width: _logoWidth, excludeFromSemantics: true),
              const SizedBox(width: BrookieSpace.s5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Brooke Stapleton Photography', style: text.titleMedium),
                    const SizedBox(height: BrookieSpace.s1),
                    Text(
                      '© ${DateTime.now().year} Brooke Stapleton Photography',
                      style: text.bodySmall?.copyWith(color: c.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
