// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:parklibre/main.dart';

void main() {
  testWidgets('ParkLibre app widget tree is correct', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ParkLibreApp());

    expect(find.byType(ParkLibreApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
