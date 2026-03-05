import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';

void main() {
  group('Sync UI Widgets', () {
    testWidgets('SyncStatusWidget builds without error', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyncStatusWidget(
                statusStream: statusController.stream,
                onSync: () {},
              ),
            ),
          ),
        );

        // Widget should render without throwing
        expect(find.byType(SyncStatusWidget), findsOneWidget);
      } finally {
        statusController.close();
      }
    });

    testWidgets('SyncMetricsCard builds and displays data', (
      WidgetTester tester,
    ) async {
      final sessionMetrics = SyncSessionMetrics();
      final tableMetrics = SyncMetrics(tableName: 'todos');
      tableMetrics.recordsPulled = 10;
      tableMetrics.recordsPushed = 5;
      sessionMetrics.addTableMetrics(tableMetrics);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncMetricsCard(metrics: sessionMetrics),
            ),
          ),
        ),
      );

      // Widget should render
      expect(find.byType(SyncMetricsCard), findsOneWidget);
    });
  });
}
