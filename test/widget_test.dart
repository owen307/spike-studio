import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spike_prime_studio/main.dart';

void main() {
  testWidgets('studio opens the sample project on a mock hub', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SpikeStudioApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Spike Prime Studio'), findsWidgets);
    expect(find.text('Drive and look'), findsWidgets);
    expect(find.text('Before you connect'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Before you connect'), findsNothing);
    expect(find.text('when program starts'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
