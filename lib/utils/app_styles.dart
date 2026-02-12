import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const mainColor = Color.fromARGB(255, 0, 109, 111);

  static const bgColor = Color.fromARGB(255, 250, 250, 250);

  static const secondaryColor = Color.fromARGB(255, 19, 173, 175);

  static const gradient = LinearGradient(
    colors: [
      Color.fromARGB(255, 21, 164, 55),
      Color.fromRGBO(35, 95, 217, 0.749),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const Color forAppBar = Color.fromARGB(255, 67, 152, 155);

  static const Color forElevatedButton = Color.fromARGB(255, 67, 152, 155);

  static const Color accentGold = Color.fromARGB(255, 255, 204, 102);

  static const Color accentCoral = Color.fromARGB(255, 255, 140, 100);

  static const Color neutralLightGrey = Color.fromARGB(255, 240, 240, 240);

  static const Color neutralDarkGrey = Color.fromARGB(255, 80, 80, 80);

  static const Color neutralCharcoal = Color.fromARGB(255, 30, 30, 30);

  static const Color backgroundOffWhite = Color.fromARGB(255, 250, 250, 245);

  static const Color tertiaryViolet = Color.fromARGB(255, 150, 140, 200);

  // /// The primary start color for the main theme gradient.
  // /// Represents a vibrant green shade: ARGB(255, 21, 164, 55).
  // static const Color primaryGreen = Color.fromARGB(255, 21, 164, 55);

  // /// The primary end color for the main theme gradient.
  // /// Represents a dynamic blue shade with transparency: RGBA(35, 95, 217, 0.749).
  // static const Color primaryBlue = Color.fromRGBO(35, 95, 217, 0.749);

  // /// Generates a list of colors forming a gradient between two given colors.
  // ///
  // /// [startColor]: The starting color of the gradient.
  // /// [endColor]: The ending color of the gradient.
  // /// [steps]: The number of steps (colors) in the gradient. Must be at least 2.
  // static List<Color> _generateGradient(Color startColor, Color endColor, int steps) {
  //   assert(steps >= 2, 'Gradient must have at least 2 steps.');

  //   final List<Color> gradientColors = [];
  //   for (int i = 0; i < steps; i++) {
  //     final double t = i / (steps - 1); // Interpolation factor
  //     final int r = (startColor.red + (endColor.red - startColor.red) * t).round();
  //     final int g = (startColor.green + (endColor.green - startColor.green) * t).round();
  //     final int b = (startColor.blue + (endColor.blue - startColor.blue) * t).round();
  //     final int a = (startColor.alpha + (endColor.alpha - startColor.alpha) * t).round();
  //     gradientColors.add(Color.fromARGB(a, r, g, b));
  //   }
  //   return gradientColors;
  // }

  // /// The main theme gradient palette, transitioning from a vibrant green to a dynamic blue.
  // /// This palette provides 5 steps for a smooth visual transition.
  // static List<Color> mainThemeGradient = _generateGradient(primaryGreen, primaryBlue, 5);

  // /// A lighter variation of the main theme gradient, suitable for backgrounds or subtle accents.
  // /// This uses a slightly desaturated version of the primary colors for a softer look.
  // static List<Color> lightThemeGradient = _generateGradient(
  //   primaryGreen.withOpacity(0.7), // Slightly more transparent green
  //   primaryBlue.withOpacity(0.5),  // More transparent blue
  //   5,
  // );

  // /// A darker variation of the main theme gradient, suitable for text or strong elements.
  // /// This uses a slightly darker version of the primary colors.
  // static List<Color> darkThemeGradient = _generateGradient(
  //   Color.fromARGB(primaryGreen.alpha, (primaryGreen.red * 0.7).round(), (primaryGreen.green * 0.7).round(), (primaryGreen.blue * 0.7).round()),
  //   Color.fromARGB(primaryBlue.alpha, (primaryBlue.red * 0.7).round(), (primaryBlue.green * 0.7).round(), (primaryBlue.blue * 0.7).round()),
  //   5,
  // );

  // static const Color dark = Color(0xFF1E1E1E);
  // static const Color medium = Color(0x50FFFFFF);
  // static const Color light = Color(0xFFFFFFFF);
  // static const Color accent = Color.fromARGB(255, 65, 155, 194);

  // static const Color disabledBackgroundColor = Colors.black12;
  // static const Color disabledForegroundColor = Colors.white12;

  // static const gradient = LinearGradient(
  //   colors: [
  //     Color.fromARGB(255, 21, 164, 55),
  //     Color.fromRGBO(35, 95, 217, 0.749),
  //   ],
  //   begin: Alignment.topCenter,
  //   end: Alignment.bottomCenter,
  // );

  // static const TextStyle inputStyle = TextStyle(color: light, fontSize: 20);
  // static const TextStyle hintStyle = TextStyle(color: medium);
  // static const TextStyle counterStyle = TextStyle(color: medium, fontSize: 14);
  // static const TextStyle splashstyle = TextStyle(
  //   color: accent,
  //   fontSize: 60,
  //   fontStyle: FontStyle.italic,
  //   fontWeight: FontWeight.w500,
  // );
}
