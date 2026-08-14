import 'package:flutter/material.dart';

/// Font pairing + micro type-scale extracted from the legacy app
/// (DISCOVERY_REPORT.md §3): Inter for body/UI, Space Grotesk for
/// headings/display, sized close to the iOS Human Interface Guidelines scale.
/// Both fonts are bundled locally (pubspec.yaml `fonts:`) rather than fetched
/// at runtime — see the comment there for why.
class AppTextStyles {
  AppTextStyles._();

  static const _display = 'SpaceGrotesk';
  static const _body = 'Inter';

  static const TextStyle display = TextStyle(
    fontFamily: _display,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _display,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _display,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _body,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _body,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _body,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: _body,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.4,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _body,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}
