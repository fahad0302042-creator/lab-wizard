import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/features/widgets/widget_link.dart';

void main() {
  group('parseWidgetLink', () {
    test('reads widget hosts and item ids', () {
      expect(
        parseWidgetLink(Uri.parse('labwizard://scan_consume')).action,
        WidgetLinkAction.scan,
      );
      expect(
        parseWidgetLink(Uri.parse('labwizard://search')).action,
        WidgetLinkAction.search,
      );
      expect(
        parseWidgetLink(Uri.parse('labwizard://undo')).mutatesInventory,
        isTrue,
      );
      expect(
        parseWidgetLink(Uri.parse('labwizard://dashboard')).action,
        WidgetLinkAction.dashboard,
      );

      final item = parseWidgetLink(Uri.parse('labwizard://item?id=chem-1'));
      expect(item.action, WidgetLinkAction.item);
      expect(item.itemId, 'chem-1');
      expect(item.mutatesInventory, isFalse);
    });

    test('unknown and empty item links do not change stock', () {
      expect(
        parseWidgetLink(Uri.parse('labwizard://nope')).action,
        WidgetLinkAction.dashboard,
      );
      expect(parseWidgetLink(Uri.parse('labwizard://item')).itemId, isNull);
      expect(parseWidgetLink(Uri.parse('labwizard://item?id=')).itemId, isNull);
    });
  });

  group('widgetLinkMayRun', () {
    test('holds the link until the signed-in notebook is visible', () {
      expect(
        widgetLinkMayRun(signedIn: true, lockReady: true, locked: false),
        isTrue,
      );
      expect(
        widgetLinkMayRun(signedIn: true, lockReady: false, locked: false),
        isFalse,
      );
      expect(
        widgetLinkMayRun(signedIn: true, lockReady: true, locked: true),
        isFalse,
      );
      expect(
        widgetLinkMayRun(signedIn: false, lockReady: true, locked: false),
        isFalse,
      );
    });
  });
}
