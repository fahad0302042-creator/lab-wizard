/// Turns raw exceptions from Supabase/SQLite into short, human messages.
///
/// Lives in `core` so every surface — sheets, screens, printing — reports
/// failures the same way instead of each growing its own copy.
String friendlyError(Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^[A-Za-z]+Exception:\s*'),
    '',
  );
  final lower = message.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('host lookup')) {
    return 'You appear to be offline. The change will sync when possible.';
  }
  if (lower.contains('permission') || lower.contains('row-level security')) {
    return 'This account does not have permission to change that item.';
  }
  return message.isEmpty ? 'Something went wrong. Please try again.' : message;
}
