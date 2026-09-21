/// Turns repository and network exceptions into short notebook-style copy.
String friendlyErrorMessage(Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^[A-Za-z]+Exception:\s*'),
    '',
  );
  final lower = message.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('host lookup') ||
      lower.contains('timed out')) {
    return 'You appear to be offline. The change will sync when possible.';
  }
  if (lower.contains('permission') || lower.contains('row-level security')) {
    return 'This account does not have permission to change that item.';
  }
  if (lower.contains('insufficient stock')) {
    return 'The server has less stock than this change needs.';
  }
  if (lower.contains('not found')) {
    return 'The item no longer exists on the server.';
  }
  return message.isEmpty ? 'Something went wrong. Please try again.' : message;
}
