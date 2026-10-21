import 'dart:math' as math;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'search.dart';
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

/// A heading inside a bottom sheet, set apart from the control below it.
class SheetLabel extends StatelessWidget {
  final String text;
  const SheetLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text,
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
    );
  }
}

/// A row that isn't a tile (a slider, a color picker) with the words a
/// [ListFilter] should find it by.
class FilterKeywords extends StatelessWidget {
  final List<String> keywords;
  final Widget child;
  const FilterKeywords({super.key, required this.keywords, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// A settings group: inset-grouped on iOS, a titled card elsewhere.
///
/// With [onExpandedChanged] it folds: the header shows a chevron and opens
/// or closes the group, which shows only its header while closed. A search
/// above (a [ListFilter]) opens the groups it matches.
class AdaptiveSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final IconData? icon;
  final List<Widget> children;
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;
  const AdaptiveSection({
    super.key,
    this.header,
    this.footer,
    this.icon,
    required this.children,
    this.expanded = true,
    this.onExpandedChanged,
  });

  /// The rows a [ListFilter] above leaves: all of them when the header
  /// matches, otherwise the tiles whose title or subtitle does.
  List<Widget> _visible(BuildContext context, SearchQuery? q) {
    // Each text in the interface language and in the English it was
    // translated from.
    List<String?> both(List<String?> texts) => [for (final t in texts) ...[t, if (t != null) englishOf(t)]];
    if (q == null || q.matches(both([header]))) return children;
    return [
      for (final c in children)
        if (c is AdaptiveSwitchTile && q.matches(both([c.title, c.subtitle])) ||
            c is AdaptiveNavTile && q.matches(both([c.title, c.subtitle])) ||
            c is FilterKeywords && q.matches(both(c.keywords)))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = ListFilter.of(context);
    final children = _visible(context, q);
    if (children.isEmpty) return const SizedBox.shrink();
    final foldable = onExpandedChanged != null && header != null && q == null;
    final open = !foldable || expanded;
    final theme = Theme.of(context);
    final cupertino = isCupertinoPlatform;

    Widget? title;
    if (header != null) {
      final text = Text(
        cupertino ? header!.toUpperCase() : header!,
        style: cupertino ? null : theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      );
      title = !foldable
          ? text
          : Semantics(
              button: true,
              expanded: open,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onExpandedChanged!(!open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: cupertino ? null : theme.colorScheme.primary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: text),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, size: 22, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
            );
    }

    Widget body;
    if (cupertino) {
      body = !open
          ? Padding(padding: const EdgeInsets.fromLTRB(36, 8, 28, 4), child: DefaultTextStyle.merge(
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(fontSize: 13, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
              child: title!))
          : CupertinoListSection.insetGrouped(
              header: title,
              footer: footer == null ? null : Text(footer!),
              backgroundColor: theme.scaffoldBackgroundColor,
              children: children,
            );
    } else {
      body = Padding(
        padding: EdgeInsets.fromLTRB(16, open ? 8 : 2, 16, open ? 8 : 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) Padding(padding: EdgeInsets.fromLTRB(8, foldable ? 2 : 8, 8, foldable ? 0 : 6), child: title),
          if (open) Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
          if (open && footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall),
            ),
        ]),
      );
    }
    return foldable
        ? AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut, alignment: Alignment.topCenter, child: body)
        : body;
  }
}

/// UIKit's own alerts and action sheets (UIAlertController), in Liquid Glass
/// from iOS 26.
bool get _nativeAlerts => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<bool> showAdaptiveConfirm(BuildContext context, {required String title, String? message, String confirm = 'OK'}) async {
  if (_nativeAlerts) {
    final r = await CNAlert.show<bool>(context: context, title: title, message: message, actions: [
      CNAlertAction(label: context.tr('Cancel'), value: false, isCancel: true),
      CNAlertAction(label: context.tr(confirm), value: true, isDefault: true),
    ]);
    return r?.value ?? false;
  }
  final r = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        _action(ctx, ctx.tr('Cancel'), () => Navigator.pop(ctx, false)),
        _action(ctx, ctx.tr(confirm), () => Navigator.pop(ctx, true), isDefault: true),
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
  if (_nativeAlerts) {
    // An action sheet has no checkmarks; the current choice is marked in its
    // label. On an iPad it points at the row that opened it.
    final box = context.findRenderObject();
    return CNActionSheet.show<T>(
      context: context,
      anchorRect: box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
      title: title,
      cancelLabel: context.tr('Cancel'),
      actions: [for (final (v, label) in options) CNActionSheetAction(label: v == selected ? '✓ $label' : label, value: v)],
    );
  }
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
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('Cancel'))),
      ),
    );
  }
  // Above the tab bar, with a heading that stands apart from the options.
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            const SizedBox(height: 4),
            for (final (v, label) in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(label,
                    style: v == selected ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600) : null),
                trailing: v == selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ]),
        ),
      );
    },
  );
}

Widget adaptiveProgress() => const Center(child: CircularProgressIndicator.adaptive());

/// One of an app bar's tools, for [fitBarActions].
class BarTool {
  final String tooltip;
  final Widget icon;
  final Widget? selectedIcon;
  final bool? isSelected;
  final VoidCallback? onPressed;

  /// A tool of its own (a menu), always kept on the bar.
  final Widget? custom;

  const BarTool({required this.tooltip, required this.icon, this.selectedIcon, this.isSelected, required this.onPressed})
      : custom = null;
  const BarTool.custom(Widget this.custom)
      : tooltip = '',
        icon = const SizedBox.shrink(),
        selectedIcon = null,
        isSelected = null,
        onPressed = null;
}

/// An app bar's [tools], in their order on the bar. Where they would cut
/// the [title] short (narrow phones, large text: "Shach…"), those listed
/// in [spare], first first, go into a "More" menu instead.
List<Widget> fitBarActions(BuildContext context, String title, List<BarTool> tools, {required List<int> spare}) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  // Room for the whole title, or about nine letters of a long one, beside
  // the back button and the title's spacing.
  final need = math.min(textWidth(context, title, Theme.of(context).appBarTheme.titleTextStyle ?? Theme.of(context).textTheme.titleLarge),
          120 * scale) +
      8;
  final fit = ((MediaQuery.sizeOf(context).width - 72 - need) / 48).floor();
  final menu = tools.length <= fit ? const <int>{} : spare.take(math.max(0, tools.length - math.max(0, fit - 1))).toSet();
  Widget icon(BarTool t) => t.isSelected == true ? t.selectedIcon ?? t.icon : t.icon;
  return [
    for (final (i, t) in tools.indexed)
      if (!menu.contains(i))
        t.custom ??
            IconButton(tooltip: t.tooltip, icon: t.icon, selectedIcon: t.selectedIcon, isSelected: t.isSelected, onPressed: t.onPressed),
    if (menu.isNotEmpty)
      PopupMenuButton<VoidCallback>(
        tooltip: context.tr('More'),
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          for (final (i, t) in tools.indexed)
            if (menu.contains(i) && t.onPressed != null) PopupMenuItem(value: t.onPressed, child: ListTile(leading: icon(t), title: Text(t.tooltip))),
        ],
      ),
  ];
}

/// How wide [text] is set on one line in [style] at the reader's text size,
/// for layouts that choose how many columns fit.
double textWidth(BuildContext context, String text, TextStyle? style) {
  final p = TextPainter(
      text: TextSpan(text: text, style: style), textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
    ..layout();
  final w = p.width;
  p.dispose();
  return w;
}

/// The widest single word of [texts], so a layout can keep from breaking a
/// word in the middle.
double widestWord(BuildContext context, Iterable<String> texts, TextStyle? style) => texts
    .expand((t) => t.split(RegExp(r'\s+')))
    .fold(0.0, (w, word) => math.max(w, textWidth(context, word, style)));

/// A single choice among a few options: a segmented bar when the labels
/// fit on one line, otherwise chips that wrap, so long labels, large text
/// or narrow phones never squeeze them into broken words.
class ChoiceBar<T> extends StatelessWidget {
  final List<(T, String, IconData?)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const ChoiceBar({super.key, required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return LayoutBuilder(builder: (context, c) {
      // Each segment needs its label, optional icon and padding; the bar
      // divides the width evenly, so the widest segment decides.
      final widest = options.fold(0.0, (w, o) => math.max(w, textWidth(context, o.$2, style) + (o.$3 != null ? 26 : 0)));
      if ((widest + 32) * options.length <= c.maxWidth) {
        return SegmentedButton<T>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: [
            for (final (v, label, icon) in options) ButtonSegment(value: v, label: Text(label, maxLines: 1), icon: icon == null ? null : Icon(icon)),
          ],
          selected: {selected},
          onSelectionChanged: (v) => onChanged(v.first),
        );
      }
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (v, label, icon) in options)
          ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 18),
            label: Text(label),
            selected: v == selected,
            showCheckmark: false,
            onSelected: (_) => onChanged(v),
          ),
      ]);
    });
  }
}
