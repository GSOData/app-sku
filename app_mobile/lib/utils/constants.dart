import 'package:flutter/material.dart';

class Constants {
  /// URL base da API
  /// Alterado para o seu IP local para funcionar no celular físico via Wi-Fi
  static const String apiUrl = 'http://192.168.15.52:8000/api/';
}

/// Chaves para SharedPreferences
class StorageKeys {
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userData = 'user_data';
}

/// Cores do aplicativo - Material Design 3
class AppColors {
  // Cores primárias - Azul Marinho
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryLight = Color(0xFF534BAE);
  static const Color primaryDark = Color(0xFF000051);
  static const Color onPrimary = Colors.white;

  // Cores secundárias - Laranja
  static const Color secondary = Color(0xFFFF6F00);
  static const Color secondaryLight = Color(0xFFFFA040);
  static const Color secondaryDark = Color(0xFFC43E00);
  static const Color onSecondary = Colors.white;

  // Cores de status
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Cores de status de validade (vindas do backend)
  static const Color statusVencido = Color(0xFF000000);
  static const Color statusCritico = Color(0xFFF44336);
  static const Color statusPreBloqueio = Color(0xFFFFC107);
  static const Color statusOk = Color(0xFF4CAF50);
  static const Color statusSemEstoque = Color(0xFF9E9E9E);

  // Cores neutras
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFBDBDBD);

  /// Converte cor hexadecimal (string) para Color
  /// Usado para cores vindas do backend
  static Color fromHex(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }
}

/// Espaçamentos padrão
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

/// Tamanhos de fonte
class AppFontSizes {
  static const double caption = 12.0;
  static const double body = 14.0;
  static const double subtitle = 16.0;
  static const double title = 20.0;
  static const double headline = 24.0;
  static const double display = 32.0;
}

/// Bordas arredondadas
class AppRadius {
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double circular = 100.0;
}
