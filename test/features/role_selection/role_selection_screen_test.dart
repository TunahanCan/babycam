import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:babycam/app/app_role.dart';
import 'package:babycam/core/theme/babycam_colors.dart';
import 'package:babycam/features/role_selection/role_selection_screen.dart';

void main() {
  testWidgets('RoleSelectionScreen iki kart ve mavi/pembe tema gösterir', (tester) async {
    AppRole? selected;
    await tester.pumpWidget(MaterialApp(home: RoleSelectionScreen(onRoleSelected: (role) => selected = role)));
    expect(find.text('Ebeveyn Cihazı'), findsOneWidget);
    expect(find.text('Bebek Odası Cihazı'), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart), findsOneWidget);
    expect(find.byIcon(Icons.child_care), findsOneWidget);
    expect(BabyCamColors.brandBlue, const Color(0xFF5AA9FF));
    expect(BabyCamColors.brandPink, const Color(0xFFFF7BBF));
    await tester.tap(find.text('Ebeveyn Cihazı'));
    expect(selected, AppRole.client);
  });
}
