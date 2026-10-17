import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// The signed-in family's initial on a butter disc, like the logo's.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.user, this.size = BrookieSize.controlSm});

  final AppUser user;

  /// Diameter. The top bar's avatar is [BrookieSize.controlSm].
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    // A larger disc takes a larger initial so it keeps the same proportions.
    final style = size > BrookieSize.controlSm ? BrookieType.title : BrookieType.label;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.butter,
      foregroundColor: c.onButter,
      // The name beside it, or the button's tooltip, already says who this is.
      child: ExcludeSemantics(child: Text(user.initial, style: style.copyWith(color: c.onButter))),
    );
  }
}
