import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/widgets/widget_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseDate = DateTime(2026, 9, 22, 14, 30);

  final testChemicals = <Chemical>[
    Chemical(
      id: 'chem-1',
      name: 'Ethanol 99.8%',
      formula: 'C2H5OH',
      unit: 'mL',
      quantity: 1200,
      initialQuantity: 1500,
      lowStockThreshold: 200,
      notes: '',
      qrCode: 'qr-chem-1',
      createdAt: baseDate,
    ),
    Chemical(
      id: 'chem-2',
      name: 'Acetone',
      formula: 'C3H6O',
      unit: 'mL',
      quantity: 50,
      initialQuantity: 500,
      lowStockThreshold: 100, // Low stock! (50 <= 100)
      notes: '',
      qrCode: 'qr-chem-2',
      createdAt: baseDate,
    ),
  ];

  final testApparatus = <Apparatus>[
    Apparatus(
      id: 'app-1',
      name: 'Erlenmeyer 250mL',
      category: 'Glassware',
      quantity: 15,
      initialQuantity: 20,
      lowStockThreshold: 5,
      notes: '',
      createdAt: baseDate,
    ),
  ];

  group('computeConsumptionWidgetData', () {
    test('computes empty consumption state with ready speech', () {
      final payload = computeConsumptionWidgetData(
        labName: 'Organic Chem Lab',
        chemicals: [testChemicals[0]], // Healthy stock
        apparatus: testApparatus,
        logs: const [],
        now: baseDate,
      );

      expect(payload['lab_name'], 'Organic Chem Lab');
      expect(payload['today_header'], "TODAY'S CONSUMPTION");
      expect(payload['flaskie_speech'], 'Ready to experiment!');
      expect(payload['flaskie_frame'], 0);
      expect(payload['item_1_name'], '');
      expect(payload['item_1_used'], '');
      expect(payload['item_1_remaining'], '');
    });

    test('falls back to default lab name if empty', () {
      final payload = computeConsumptionWidgetData(
        labName: '   ',
        chemicals: [testChemicals[0]],
        apparatus: testApparatus,
        logs: const [],
        now: baseDate,
      );

      expect(payload['lab_name'], 'Lab Wizard');
    });

    test('aggregates today consumption logs, sorts top items, and ignores restocks', () {
      final logs = <ConsumptionLog>[
        // Today's consumption on chem-1 (100 mL)
        ConsumptionLog(
          id: 'log-1',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 100,
          note: 'Titration 1',
          loggedAt: DateTime(2026, 9, 22, 10, 0),
          createdAt: DateTime(2026, 9, 22, 10, 0),
        ),
        // Additional consumption on chem-1 (50 mL) -> Total 150 mL
        ConsumptionLog(
          id: 'log-2',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 50,
          note: 'Titration 2',
          loggedAt: DateTime(2026, 9, 22, 11, 0),
          createdAt: DateTime(2026, 9, 22, 11, 0),
        ),
        // Today's breakage on apparatus app-1 (2 pcs)
        ConsumptionLog(
          id: 'log-3',
          itemId: 'app-1',
          itemType: ItemKind.apparatus,
          action: InventoryAction.breakage,
          amount: 2,
          note: 'Benchtop drop',
          loggedAt: DateTime(2026, 9, 22, 12, 0),
          createdAt: DateTime(2026, 9, 22, 12, 0),
        ),
        // Restock on chem-1 should NOT count as consumption
        ConsumptionLog(
          id: 'log-4',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.restock,
          amount: 500,
          note: 'Supplier batch',
          loggedAt: DateTime(2026, 9, 22, 13, 0),
          createdAt: DateTime(2026, 9, 22, 13, 0),
        ),
        // Consumption from yesterday should NOT count
        ConsumptionLog(
          id: 'log-5',
          itemId: 'chem-1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 200,
          note: 'Yesterday experiment',
          loggedAt: DateTime(2026, 9, 21, 15, 0),
          createdAt: DateTime(2026, 9, 21, 15, 0),
        ),
      ];

      final payload = computeConsumptionWidgetData(
        labName: 'Central Lab',
        chemicals: [testChemicals[0]], // Healthy stock
        apparatus: testApparatus,
        logs: logs,
        now: baseDate,
      );

      expect(payload['today_header'], 'TODAY: 2 items (3 uses)');
      expect(payload['flaskie_speech'], '2 used today! Keep it up!');
      expect(payload['flaskie_frame'], 2);

      // Top item is chem-1 (150 mL used)
      expect(payload['item_1_id'], 'chem-1');
      expect(payload['item_1_name'], 'Ethanol 99.8%');
      expect(payload['item_1_used'], '-150 mL');
      expect(payload['item_1_remaining'], '(1200 mL left)');

      // Second item is app-1 (2 pcs used)
      expect(payload['item_2_id'], 'app-1');
      expect(payload['item_2_name'], 'Erlenmeyer 250mL');
      expect(payload['item_2_used'], '-2 pcs');
      expect(payload['item_2_remaining'], '(15 pcs left)');

      // Third item is empty
      expect(payload['item_3_id'], '');
      expect(payload['item_3_name'], '');
    });

    test('prioritizes low stock alert in Flaskie speech', () {
      final payload = computeConsumptionWidgetData(
        labName: 'Central Lab',
        chemicals: testChemicals, // chem-2 is low stock!
        apparatus: testApparatus,
        logs: const [],
        now: baseDate,
      );

      expect(payload['flaskie_speech'], 'Low on Acetone!');
      expect(payload['flaskie_frame'], 1);
    });
  });

  group('WidgetGateway platform channel', () {
    test('invokes updateWidget with payload over MethodChannel', () async {
      Map<Object?, Object?>? receivedArguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WidgetGateway.channel, (call) async {
            if (call.method == 'updateWidget') {
              receivedArguments = call.arguments as Map<Object?, Object?>?;
              return true;
            }
            if (call.method == 'getInitialUri') {
              return 'labwizard://scan_consume';
            }
            return null;
          });

      final success = await WidgetGateway.updateWidget(
        labName: 'Lab Alpha',
        chemicals: [testChemicals[0]],
        apparatus: testApparatus,
        logs: const [],
        now: baseDate,
      );

      expect(success, isTrue);
      expect(receivedArguments?['lab_name'], 'Lab Alpha');

      final initialUri = await WidgetGateway.getInitialUri();
      expect(initialUri?.toString(), 'labwizard://scan_consume');

      // Test deep link registration
      Uri? handledUri;
      WidgetGateway.registerDeepLinkHandler((uri) {
        handledUri = uri;
      });

      // Simulate incoming deep link from native Android intent
      final byteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onDeepLink', 'labwizard://undo'),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(WidgetGateway.channelName, byteData, (_) {});

      expect(handledUri?.toString(), 'labwizard://undo');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WidgetGateway.channel, null);
    });
  });
}
