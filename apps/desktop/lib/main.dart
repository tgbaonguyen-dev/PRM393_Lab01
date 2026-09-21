import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shared/notion_tokens.dart';
import 'shell/app_shell.dart';

void main() {
  runApp(const Prm393DesktopApp());
}

class Prm393DesktopApp extends StatelessWidget {
  const Prm393DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.light().textTheme;
    final interTextTheme = GoogleFonts.interTextTheme(
      baseTextTheme,
    ).apply(bodyColor: NotionColors.ink, displayColor: NotionColors.ink);

    return MaterialApp(
      title: 'iPresent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: NotionColors.canvasSoft,
        textTheme: interTextTheme,
        colorScheme: const ColorScheme.light(
          primary: NotionColors.primary,
          surface: NotionColors.surface,
          onPrimary: NotionColors.onPrimary,
          onSurface: NotionColors.ink,
        ),
        dividerColor: NotionColors.hairline,
        dividerTheme: const DividerThemeData(
          color: NotionColors.hairline,
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: NotionColors.surface,
          hintStyle: NotionTypography.caption(color: NotionColors.inkFaint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: NotionColors.inkSecondary,
            textStyle: NotionTypography.buttonUtility(),
            shape: RoundedRectangleBorder(
              borderRadius: NotionRounded.md,
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: NotionColors.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: NotionRounded.md,
            side: const BorderSide(color: NotionColors.hairline),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          dividerThickness: 1,
          headingRowColor: WidgetStateProperty.all(NotionColors.canvasSoft),
          headingTextStyle: NotionTypography.eyebrow(),
          dataTextStyle: NotionTypography.bodySm(),
        ),
        cardTheme: CardThemeData(
          color: NotionColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: NotionRounded.lg,
            side: const BorderSide(color: NotionColors.hairline, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: NotionColors.surface,
            foregroundColor: NotionColors.ink,
            side: const BorderSide(color: NotionColors.hairline, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: NotionTypography.buttonUtility(),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: NotionColors.primary,
            foregroundColor: NotionColors.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: NotionTypography.buttonUtility().copyWith(
              color: NotionColors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
