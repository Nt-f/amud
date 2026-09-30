import 'package:flutter/material.dart';

import '../../../core/l10n.dart';

/// Shared chrome for dashboard cards.
class CardFrame extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? accent;
  const CardFrame({super.key, this.title, this.icon, required this.child, this.onTap, this.trailing, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: accent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: theme.colorScheme.primary), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(context.tr(title!),
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.3),
                        overflow: TextOverflow.ellipsis),
                  ),
                  ?trailing,
                ]),
              ),
            child,
          ]),
        ),
      ),
    );
  }
}
