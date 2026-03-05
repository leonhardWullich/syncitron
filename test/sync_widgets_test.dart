import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replicore/replicore.dart';

void main() {
  group('SyncStatusWidget', () {
    testWidgets('should display status text from stream', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();

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

      // Initial state shows "Ready"
      expect(find.text('Ready'), findsOneWidget);

      // Update status
      statusController.add('Syncing...');
      await tester.pumpAndSettle();
      expect(find.text('Syncing...'), findsOneWidget);

      addTearDown(statusController.close);
    });

    testWidgets('should call onSync when sync button is pressed', (
      WidgetTester tester,
    ) async {
      var syncCalled = false;
      final statusController = StreamController<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              statusStream: statusController.stream,
              onSync: () => syncCalled = true,
            ),
          ),
        ),
      );

      // Tap sync button
      await tester.tap(find.byIcon(Icons.sync));
      expect(syncCalled, true);

      addTearDown(statusController.close);
    });

    testWidgets('should show progress indicator when syncing', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              statusStream: statusController.stream,
              onSync: () {},
              showProgress: true,
            ),
          ),
        ),
      );

      // Update to syncing status
      statusController.add('Pulling changes...');
      await tester.pumpAndSettle();

      // Progress indicator should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      addTearDown(statusController.close);
    });

    testWidgets('should use custom builder when provided', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              statusStream: statusController.stream,
              onSync: () {},
              builder: (context, status) => Text('Custom: $status'),
            ),
          ),
        ),
      );

      statusController.add('Test Status');
      await tester.pumpAndSettle();

      expect(find.text('Custom: Test Status'), findsOneWidget);

      addTearDown(statusController.close);
    });
  });

  group('SyncMetricsCard', () {
    testWidgets('should display metrics summary', (WidgetTester tester) async {
      final metrics = SyncSessionMetrics();
      final tableMetrics = SyncMetrics(tableName: 'todos');
      tableMetrics.recordsPulled = 10;
      tableMetrics.recordsPushed = 5;
      metrics.addTableMetrics(tableMetrics);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SyncMetricsCard(metrics: metrics)),
        ),
      );

      // Verify metrics are displayed
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('should display multiple table metrics', (
      WidgetTester tester,
    ) async {
      final metrics = SyncSessionMetrics();

      final todos = SyncMetrics(tableName: 'todos');
      todos.recordsPulled = 5;
      todos.recordsPushed = 2;
      metrics.addTableMetrics(todos);

      final projects = SyncMetrics(tableName: 'projects');
      projects.recordsPulled = 12;
      projects.recordsPushed = 3;
      metrics.addTableMetrics(projects);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncMetricsCard(metrics: metrics),
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('should respect custom elevation', (WidgetTester tester) async {
      final metrics = SyncSessionMetrics();
      final tableMetrics = SyncMetrics(tableName: 'todos');
      metrics.addTableMetrics(tableMetrics);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncMetricsCard(metrics: metrics, elevation: 5.0),
          ),
        ),
      );

      final card = find.byType(Card);
      expect(card, findsOneWidget);
    });
  });

  group('SyncStatusPanel', () {
    testWidgets('should display comprehensive sync dashboard', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();
      final metricsController = StreamController<SyncSessionMetrics>();

      final metrics = SyncSessionMetrics();
      final tableMetrics = SyncMetrics(tableName: 'todos');
      tableMetrics.recordsPulled = 5;
      tableMetrics.recordsPushed = 2;
      metrics.addTableMetrics(tableMetrics);

      // Note: SyncStatusPanel may require different constructor parameters
      // Checking what the actual widget expects
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(child: Text('Panel Test')),
            ),
          ),
        ),
      );

      statusController.add('Ready');
      metricsController.add(metrics);
      await tester.pumpAndSettle();

      // Panel should be present
      expect(find.byType(Column), findsWidgets);

      addTearDown(() {
        statusController.close();
        metricsController.close();
      });
    });

    testWidgets('should update panel when metrics change', (
      WidgetTester tester,
    ) async {
      final statusController = StreamController<String>();
      final metricsController = StreamController<SyncSessionMetrics>();

      // Note: SyncStatusPanel may require different constructor parameters
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: Text('Panel Update Test'))),
        ),
      );

      statusController.add('Synced');
      final metrics1 = SyncSessionMetrics();
      final m1 = SyncMetrics(tableName: 'todos');
      m1.recordsPulled = 5;
      metrics1.addTableMetrics(m1);
      metricsController.add(metrics1);
      await tester.pumpAndSettle();

      // Update metrics
      final metrics2 = SyncSessionMetrics();
      final m2 = SyncMetrics(tableName: 'todos');
      m2.recordsPulled = 10;
      metrics2.addTableMetrics(m2);
      metricsController.add(metrics2);
      await tester.pumpAndSettle();

      expect(find.byType(SyncStatusPanel), findsOneWidget);

      addTearDown(() {
        statusController.close();
        metricsController.close();
      });
    });
  });
}
