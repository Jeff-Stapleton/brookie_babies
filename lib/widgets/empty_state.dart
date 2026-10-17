import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// What a page shows when it has nothing to show yet: one sentence that says
/// why, and the way on from it.
///
/// A quiet surface-sunk band at radius-md with s5 padding: [message] in body
/// and ink, held to the reading width, then [action] (an outlined button)
/// inside the band. Every "nothing here" state uses it, so the same situation
/// looks the same wherever it comes up.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.action});

  /// One or two short sentences, ending in a full stop.
  final String message;

  /// Usually an [OutlinedButton], such as "See packages".
  final Widget? action;

  /// The band's widest: the column "Your sessions" lists sessions in, so the
  /// band is the same size on every page.
  static const maxWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: BrookieColors.of(context).surfaceSunk,
              borderRadius: BorderRadius.circular(BrookieRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(BrookieSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
                    child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: BrookieSpace.s4),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
