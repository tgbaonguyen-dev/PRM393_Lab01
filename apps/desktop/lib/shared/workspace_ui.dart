import 'package:flutter/material.dart';
import 'notion_tokens.dart';

/// Keeps document controls and the data viewport usable in short windows.
class WorkspacePage extends StatelessWidget {
  final List<Widget> header;
  final Widget body;
  final double compactBodyHeight;
  const WorkspacePage({
    super.key,
    required this.header,
    required this.body,
    this.compactBodyHeight = 480,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final compact = size.maxHeight < 720 || size.maxWidth < 700;
      final children = <Widget>[
        ...header.expand((widget) => [widget, const SizedBox(height: NotionSpacing.md)]),
        if (compact)
          SizedBox(height: compactBodyHeight, child: body)
        else
          Expanded(child: body),
      ];
      final content = Padding(
        padding: EdgeInsets.all(size.maxWidth < 700 ? NotionSpacing.md : NotionSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
      return compact ? SingleChildScrollView(child: content) : content;
    },
  );
}

class WorkspaceHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? actions;
  final Widget? icon;
  final List<Widget>? properties;

  const WorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
    this.icon,
    this.properties,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final headerContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(height: NotionSpacing.xs),
          ],
          Text(
            title,
            style: NotionTypography.heading1(color: NotionColors.ink).copyWith(
              fontSize: size.maxWidth < 800 ? 28 : 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: NotionTypography.bodySm(color: NotionColors.inkMuted).copyWith(
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      );

      if (actions == null) {
        return headerContent;
      }

      if (size.maxWidth < 850) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerContent,
            const SizedBox(height: NotionSpacing.sm),
            actions!,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: headerContent),
          const SizedBox(width: NotionSpacing.lg),
          actions!,
        ],
      );
    },
  );
}

class WorkspaceSearch extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  const WorkspaceSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Tìm kiếm MSSV, tên, email…',
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: NotionTypography.bodySm(color: NotionColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: NotionTypography.caption(color: NotionColors.inkFaint),
        prefixIcon: const Icon(Icons.search, size: 16, color: NotionColors.inkMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        isDense: true,
        filled: true,
        fillColor: NotionColors.surface,
        border: OutlineInputBorder(
          borderRadius: NotionRounded.xs,
          borderSide: const BorderSide(color: NotionColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NotionRounded.xs,
          borderSide: const BorderSide(color: NotionColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NotionRounded.xs,
          borderSide: const BorderSide(color: NotionColors.primary, width: 1.5),
        ),
      ),
    ),
  );
}
