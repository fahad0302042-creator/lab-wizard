import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time.dart';
import '../../../core/widgets/notebook_widgets.dart';

/// Sessions card (ACCOUNT-04): what is known about this device's session
/// and the two remote sign-out controls Supabase supports.
class SessionsCard extends ConsumerStatefulWidget {
  const SessionsCard({super.key});

  @override
  ConsumerState<SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends ConsumerState<SessionsCard> {
  bool _busy = false;

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('sessions-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _signOutOthers() async {
    final ok = await _confirm(
      'Sign out other devices?',
      'Every other phone, tablet and browser will have to sign in again. '
      'This phone stays signed in.',
      'Sign out others',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref.read(authProvider.notifier).signOutOtherDevices();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Other devices were signed out.')),
    );
  }

  Future<void> _signOutEverywhere() async {
    final ok = await _confirm(
      'Sign out everywhere?',
      'All sessions end, including this phone. The offline copy on this '
      'phone is removed; your data stays in your account.',
      'Sign out everywhere',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await ref.read(authProvider.notifier).signOut(everywhere: true);
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final info = user == null ? null : SessionInfo.fromUser(user);
    final muted = context.mutedInkColor;
    final day = DateFormat('d MMM yyyy');
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_outlined, color: LabColors.marginRed),
              const SizedBox(width: 8),
              const Text(
                'sessions & devices',
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (info != null) ...[
            Row(
              children: [
                Icon(Icons.smartphone, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.signedInAt == null
                        ? 'This phone · signed in'
                        : 'This phone · signed in '
                              '${relativeTime(info.signedInAt!)}',
                    key: const Key('session-this-device'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (info.accountCreatedAt != null)
                  'Account since ${day.format(info.accountCreatedAt!.toLocal())}',
                if (info.providers.isNotEmpty)
                  'sign-in: ${info.providers.join(', ')}',
                info.emailConfirmed ? 'email confirmed' : 'email not confirmed',
              ].join(' · '),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Supabase does not show apps a list of individual devices, so '
            'other sessions cannot be listed here; they can be ended.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const Key('signout-others'),
                onPressed: _busy ? null : _signOutOthers,
                icon: const Icon(Icons.phonelink_erase_outlined),
                label: const Text('Sign out other devices'),
              ),
              OutlinedButton.icon(
                key: const Key('signout-everywhere'),
                onPressed: _busy ? null : _signOutEverywhere,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.marginRedColor,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out everywhere'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
