import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/core/theme/mimicam_colors.dart';
import 'package:mimicam/features/role_selection/role_selection_screen.dart';
import 'package:mimicam/l10n/app_strings.dart';

void main() {
  testWidgets('RoleSelectionScreen iki kart ve mavi/pembe tema gösterir',
      (tester) async {
    AppRole? selected;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RoleSelectionScreen(onRoleSelected: (role) => selected = role),
    ));
    expect(find.text('Ebeveyn Cihazı'), findsOneWidget);
    expect(find.text('Bebek Odası Cihazı'), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart), findsOneWidget);
    expect(find.byIcon(Icons.child_care), findsOneWidget);
    expect(MimiCamColors.brandBlue, const Color(0xFF5AA9FF));
    expect(MimiCamColors.brandPink, const Color(0xFFFF7BBF));
    await tester.tap(find.text('Ebeveyn Cihazı'));
    expect(selected, AppRole.client);
  });
}
