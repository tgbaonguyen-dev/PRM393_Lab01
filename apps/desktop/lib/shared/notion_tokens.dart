import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 100% Exact Design Tokens from ai/DESIGN.md (Notion Analysis)
class NotionColors {
  // Brand & Accent - Pure Black & White Notion Minimalist
  static const primary = Color(0xFF191919); // Notion Iconic Black #191919
  static const primaryActive = Color(0xFF000000); // Pure Black
  static const secondary = Color(0xFF191919); // Black
  static const onPrimary = Color(0xFFFFFFFF); // Pure White

  // Surface & Canvas
  static const canvas = Color(0xFFFFFFFF); // Pure White
  static const canvasSoft = Color(0xFFF7F7F5); // Notion Signature Paper Canvas #F7F7F5
  static const surface = Color(0xFFFFFFFF); // Crisp White
  static const hairline = Color(0xFFEBEBEA); // 1px Notion Crisp Border

  // Text
  static const ink = Color(0xFF191919); // Notion Near-black
  static const inkSecondary = Color(0xFF37352F); // Notion Primary Body
  static const inkMuted = Color(0xFF787774); // Notion Gray Text
  static const inkFaint = Color(0xFF9B9A97); // Notion Subtle Metadata

  // Monochrome & Grayscale Tag / Badge Palette (Clean Black & White)
  static const accentSky = Color(0xFF191919);
  static const accentPurple = Color(0xFF37352F);
  static const accentPurpleDeep = Color(0xFF191919);
  static const accentPink = Color(0xFF37352F);
  static const accentOrange = Color(0xFF191919);
  static const accentOrangeDeep = Color(0xFF000000);
  static const accentTeal = Color(0xFF37352F);
  static const accentGreen = Color(0xFF191919);
  static const accentBrown = Color(0xFF787774);

  // Black & White tag tints (no rainbow, pure monochrome chic)
  static const tagGreenBg = Color(0xFFF1F1EF);
  static const tagGreenText = Color(0xFF191919);
  static const tagBlueBg = Color(0xFFF1F1EF);
  static const tagBlueText = Color(0xFF191919);
  static const tagAmberBg = Color(0xFFEAEAEA);
  static const tagAmberText = Color(0xFF37352F);
  static const tagPurpleBg = Color(0xFFF1F1EF);
  static const tagPurpleText = Color(0xFF191919);
}

class NotionRounded {
  static const xs = BorderRadius.all(Radius.circular(4));
  static const sm = BorderRadius.all(Radius.circular(5));
  static const md = BorderRadius.all(Radius.circular(8));
  static const lg = BorderRadius.all(Radius.circular(12));
  static const xl = BorderRadius.all(Radius.circular(16));
  static const full = BorderRadius.all(Radius.circular(9999));

  static const double rXs = 4;
  static const double rSm = 5;
  static const double rMd = 8;
  static const double rLg = 12;
  static const double rXl = 16;
  static const double rFull = 9999;
}

class NotionSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 28;
  static const double xxl = 32;
}

class NotionTypography {
  static TextStyle display1({Color? color}) => GoogleFonts.inter(
        fontSize: 64,
        fontWeight: FontWeight.w700,
        height: 1.0,
        letterSpacing: -2.125,
        color: color ?? NotionColors.ink,
      );

  static TextStyle display2({Color? color}) => GoogleFonts.inter(
        fontSize: 54,
        fontWeight: FontWeight.w700,
        height: 1.04,
        letterSpacing: -1.875,
        color: color ?? NotionColors.ink,
      );

  static TextStyle heading1({Color? color}) => GoogleFonts.inter(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -1.0,
        color: color ?? NotionColors.ink,
      );

  static TextStyle heading2({Color? color}) => GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.23,
        letterSpacing: -0.625,
        color: color ?? NotionColors.ink,
      );

  static TextStyle heading3({Color? color}) => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.27,
        letterSpacing: -0.25,
        color: color ?? NotionColors.ink,
      );

  static TextStyle title({Color? color}) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: -0.125,
        color: color ?? NotionColors.ink,
      );

  static TextStyle bodyMd({Color? color, FontWeight? fontWeight}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: fontWeight ?? FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
        color: color ?? NotionColors.ink,
      );

  static TextStyle bodySm({Color? color, FontWeight? fontWeight}) =>
      GoogleFonts.inter(
        fontSize: 14.5,
        fontWeight: fontWeight ?? FontWeight.w400,
        height: 1.33,
        letterSpacing: 0,
        color: color ?? NotionColors.inkSecondary,
      );

  static TextStyle button({Color? color}) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.5,
        letterSpacing: 0,
        color: color ?? NotionColors.onPrimary,
      );

  static TextStyle buttonUtility({Color? color}) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0,
        color: color ?? NotionColors.inkSecondary,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0,
        color: color ?? NotionColors.inkMuted,
      );

  static TextStyle eyebrow({Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0.125,
        color: color ?? NotionColors.inkMuted,
      );
}

/// Notion Level-1 barely-there layered micro-shadow
class NotionElevation {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x03000000), // rgba(0,0,0,0.01)
      offset: Offset(0, 0.2),
      blurRadius: 1,
    ),
    BoxShadow(
      color: Color(0x05000000), // rgba(0,0,0,0.02)
      offset: Offset(0, 0.8),
      blurRadius: 3,
    ),
    BoxShadow(
      color: Color(0x07000000), // rgba(0,0,0,0.027)
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 4),
      blurRadius: 18,
    ),
  ];
}
