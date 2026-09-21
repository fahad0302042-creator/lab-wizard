import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import '../../security/app_lock_providers.dart';
import '../../security/domain/app_lock.dart';

/// App lock settings (SECURITY-01): PIN on/off, biometric shortcut, timeout,
/// change PIN and lock now.
class AppLockCard extends ConsumerWidget {
  const AppLockCard({super.key});

  Future<void> _toggle(BuildContext context, bool on) async {
    await showPinSheet(context, on ? PinSheetMode.set : PinSheetMode.disable);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final controller = ref.read(appLockProvider.notifier);
    final muted = TextStyle(color: context.mutedInkColor, fontSize: 12);
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: LabColors.marginRed),
              SizedBox(width: 8),
              Text(
                'app lock',
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ask for a PIN when Lab Wizard is opened on this phone. The PIN '
            'stays on the phone and is stored only as a salted hash in the '
            'system secure storage.',
            style: muted,
          ),
          SwitchListTile(
            key: const Key('lock-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Require a PIN to open Lab Wizard'),
            subtitle: Text(
              lock.enabled
                  ? 'On · ${lock.pinLength}-digit PIN · '
                        '${lock.timeout.label.toLowerCase()}'
                  : 'Off',
            ),
            value: lock.enabled,
            onChanged: lock.ready ? (value) => _toggle(context, value) : null,
          ),
          if (lock.enabled) ...[
            SwitchListTile(
              key: const Key('lock-biometrics'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Also unlock with fingerprint, face or the '
                  'phone screen lock'),
              subtitle: lock.biometricsAvailable
                  ? null
                  : const Text(
                      'Not available: this phone has no screen lock or '
                      'biometrics set up. The PIN keeps working.',
                    ),
              value: lock.biometrics && lock.biometricsAvailable,
              onChanged: lock.biometricsAvailable
                  ? (value) => controller.setBiometrics(value)
                  : null,
            ),
            Row(
              children: [
                const Expanded(child: Text('Lock again')),
                DropdownButton<LockTimeout>(
                  key: const Key('lock-timeout'),
                  value: lock.timeout,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final timeout in LockTimeout.values)
                      DropdownMenuItem(
                        value: timeout,
                        child: Text(timeout.label.toLowerCase()),
                      ),
                  ],
                  onChanged: (timeout) {
                    if (timeout != null) controller.setTimeout(timeout);
                  },
                ),
              ],
            ),
            Text(
              'Counted from the moment the app goes to the background. The '
              'app always locks when it is started again.',
              style: muted,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: const Key('lock-change-pin'),
                  onPressed: () => showPinSheet(context, PinSheetMode.change),
                  icon: const Icon(Icons.pin_outlined, size: 18),
                  label: const Text('Change PIN'),
                ),
                OutlinedButton.icon(
                  key: const Key('lock-now'),
                  onPressed: controller.lockNow,
                  icon: const Icon(Icons.lock, size: 18),
                  label: const Text('Lock now'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'The lock only hides the app on this phone. It does not encrypt '
            'the offline copy of your inventory or change how your data is '
            'stored in Supabase, and the app switcher may still show the '
            'last screen. Forgot the PIN? The lock screen can sign you out; '
            'the account password gets you back in.',
            style: muted,
          ),
        ],
      ),
    );
  }
}

enum PinSheetMode { set, change, disable }

/// Opens the PIN form; resolves to true when the lock changed.
Future<bool?> showPinSheet(BuildContext context, PinSheetMode mode) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NotebookSheetFrame(child: PinForm(mode: mode)),
  );
}

class PinForm extends ConsumerStatefulWidget {
  const PinForm({super.key, required this.mode});

  final PinSheetMode mode;

  @override
  ConsumerState<PinForm> createState() => _PinFormState();
}

class _PinFormState extends ConsumerState<PinForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _asksCurrent => widget.mode != PinSheetMode.set;
  bool get _asksNew => widget.mode != PinSheetMode.disable;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final controller = ref.read(appLockProvider.notifier);
    final error = switch (widget.mode) {
      PinSheetMode.set => await controller.enable(_next.text),
      PinSheetMode.change => await controller.changePin(
        current: _current.text,
        next: _next.text,
      ),
      PinSheetMode.disable => await controller.disable(_current.text),
    };
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    _current.clear();
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedInkColor;
    final (title, blurb, action) = switch (widget.mode) {
      PinSheetMode.set => (
        'set a PIN',
        'Choose $pinMinLength to $pinMaxLength digits. You will be asked '
            'for it whenever Lab Wizard opens on this phone.',
        'Turn on the lock',
      ),
      PinSheetMode.change => (
        'change PIN',
        'Confirm the current PIN, then choose a new one.',
        'Save new PIN',
      ),
      PinSheetMode.disable => (
        'turn off the lock',
        'Confirm your PIN to stop asking for it.',
        'Turn off',
      ),
    };
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SketchTitle(title, fontSize: 30),
          Text(blurb, style: TextStyle(color: muted)),
          const SizedBox(height: 14),
          if (_asksCurrent)
            _PinField(
              key: const Key('pin-current'),
              controller: _current,
              label: 'Current PIN',
              enabled: !_saving,
              autofocus: true,
              onSubmitted: _asksNew ? null : _submit,
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter your current PIN.' : null,
            ),
          if (_asksCurrent && _asksNew) const SizedBox(height: 10),
          if (_asksNew) ...[
            _PinField(
              key: const Key('pin-new'),
              controller: _next,
              label: 'New PIN',
              enabled: !_saving,
              autofocus: !_asksCurrent,
              validator: (value) => validatePin(value ?? ''),
            ),
            const SizedBox(height: 10),
            _PinField(
              key: const Key('pin-confirm'),
              controller: _confirm,
              label: 'Repeat the new PIN',
              enabled: !_saving,
              onSubmitted: _submit,
              validator: (value) =>
                  value != _next.text ? 'The PINs do not match.' : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('pin-error'),
              style: const TextStyle(
                color: LabColors.marginRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('pin-save'),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(action),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.validator,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool autofocus;
  final FormFieldValidator<String> validator;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(pinMaxLength),
      ],
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.pin_outlined),
      ),
      validator: validator,
    );
  }
}
