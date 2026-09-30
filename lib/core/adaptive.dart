import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Small set of platform-adaptive building blocks so screens use native
/// Cupertino controls on iOS/macOS and Material 3 elsewhere.

class AdaptiveSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const AdaptiveSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (isCupertinoPlatform) {
      return CupertinoListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 3),
        trailing: CupertinoSwitch(value: value, onChanged: onChanged),
      );
    }
    return SwitchListTile(title: Text(title), subtitle: subtitle == null ? null : Text(subtitle!), value: value, onChanged: onChanged);
  }
}

class AdaptiveNavTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  const AdaptiveNavTile({super.key, required this.title, this.subtitle, this.icon, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    if (isCupertinoPlatform) {
      return CupertinoListTile(
        leading: icon == null ? null : Icon(icon, size: 22),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 2),
        trailing: trailing ?? (onTap == null ? null : const CupertinoListTileChevron()),
        onTap: onTap,
      );
    }
    return ListTile(
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
      onTap: onTap,
    );
  }
}

/// A settings group: inset-grouped on iOS, a titled card elsewhere.
class AdaptiveSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  const AdaptiveSection({super.key, this.header, this.footer, required this.children});

  @override
  Widget build(BuildContext context) {
    if (isCupertinoPlatform) {
      return CupertinoListSection.insetGrouped(
        header: header == null ? null : Text(header!.toUpperCase()),
        footer: footer == null ? null : Text(footer!),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        children: children,
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(header!, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(footer!, style: theme.textTheme.bodySmall),
          ),
      ]),
    );
  }
}

Future<bool> showAdaptiveConfirm(BuildContext context, {required String title, String? message, String confirm = 'OK'}) async {
  final r = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        _action(ctx, 'Cancel', () => Navigator.pop(ctx, false)),
        _action(ctx, confirm, () => Navigator.pop(ctx, true), isDefault: true),
      ],
    ),
  );
  return r ?? false;
}

Widget _action(BuildContext ctx, String label, VoidCallback onPressed, {bool isDefault = false}) {
  if (isCupertinoPlatform) {
    return CupertinoDialogAction(isDefaultAction: isDefault, onPressed: onPressed, child: Text(label));
  }
  return TextButton(onPressed: onPressed, child: Text(label));
}

/// Picks one of [options] with a native action sheet / Material bottom sheet.
Future<T?> showAdaptivePicker<T>(BuildContext context,
    {required String title, required List<(T, String)> options, T? selected}) {
  if (isCupertinoPlatform) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final (v, label) in options)
            CupertinoActionSheetAction(
              isDefaultAction: v == selected,
              onPressed: () => Navigator.pop(ctx, v),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final (v, label) in options)
            ListTile(
              title: Text(label),
              trailing: v == selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    ),
  );
}

Widget adaptiveProgress() => const Center(child: CircularProgressIndicator.adaptive());
