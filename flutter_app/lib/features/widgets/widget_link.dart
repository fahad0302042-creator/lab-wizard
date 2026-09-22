/// Widget deep-link policy (WIDGET-01).
///
/// Pure Dart so the lock gate can be tested without the Android channel.
/// A link is held, not acted on, until a signed-in notebook is actually on
/// screen. Undo is the only action that changes stock; the shell still asks
/// before it runs.
library;

enum WidgetLinkAction { scan, search, undo, item, dashboard }

class WidgetLink {
  const WidgetLink({required this.action, this.itemId});

  final WidgetLinkAction action;

  /// Set only for [WidgetLinkAction.item].
  final String? itemId;

  bool get mutatesInventory => action == WidgetLinkAction.undo;
}

/// Reads `labwizard://scan_consume`, `labwizard://item?id=…` and the other
/// widget targets. Anything unrecognised opens the dashboard and does not
/// change stock.
WidgetLink parseWidgetLink(Uri uri) {
  final host = uri.host;
  final path = uri.path;
  final action = host.isNotEmpty
      ? host
      : (path.startsWith('/') ? path.substring(1) : path);
  switch (action) {
    case 'scan_consume':
      return const WidgetLink(action: WidgetLinkAction.scan);
    case 'search':
      return const WidgetLink(action: WidgetLinkAction.search);
    case 'undo':
      return const WidgetLink(action: WidgetLinkAction.undo);
    case 'item':
      final id = uri.queryParameters['id'];
      return WidgetLink(
        action: WidgetLinkAction.item,
        itemId: id == null || id.isEmpty ? null : id,
      );
    case 'dashboard':
    default:
      return const WidgetLink(action: WidgetLinkAction.dashboard);
  }
}

/// True only when the signed-in notebook is visible. The lock cover, and the
/// moment before stored lock settings have been read, both hold the link.
bool widgetLinkMayRun({
  required bool signedIn,
  required bool lockReady,
  required bool locked,
}) => signedIn && lockReady && !locked;
