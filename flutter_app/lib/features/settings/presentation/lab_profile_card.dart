import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../reports/domain/lab_profile.dart';
import '../../reports/lab_profile_providers.dart';

/// Opens the system picker for a PNG or JPEG logo.
Future<XFile?> pickLogoFile() {
  const group = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg'],
    mimeTypes: ['image/png', 'image/jpeg'],
  );
  return openFile(acceptedTypeGroups: const [group]);
}

/// Settings card for the report branding (REPORT-06): lab name, contact
/// line, address and an optional logo, all kept on this device only.
class LabProfileCard extends ConsumerStatefulWidget {
  const LabProfileCard({super.key, this.pickLogo = pickLogoFile});

  final Future<XFile?> Function() pickLogo;

  @override
  ConsumerState<LabProfileCard> createState() => _LabProfileCardState();
}

class _LabProfileCardState extends ConsumerState<LabProfileCard> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _address.dispose();
    super.dispose();
  }

  void _seed(LabProfile profile) {
    if (_seeded) return;
    _seeded = true;
    _name.text = profile.name;
    _contact.text = profile.contact;
    _address.text = profile.address;
  }

  Future<void> _save() {
    return ref
        .read(labProfileProvider.notifier)
        .save(
          ref
              .read(labProfileProvider)
              .copyWith(
                name: _name.text,
                contact: _contact.text,
                address: _address.text,
              ),
        );
  }

  Future<void> _chooseLogo() async {
    setState(() => _busy = true);
    try {
      final file = await widget.pickLogo();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('Please pick an image under 2 MB.');
      }
      await ref
          .read(labProfileProvider.notifier)
          .setLogo(bytes, fileName: file.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(labProfileProvider);
    ref.listen(labProfileProvider, (previous, next) {
      // Values restored from disk after the first frame land in the fields
      // as long as the person has not started typing.
      if (previous != null && previous.isEmpty && !next.isEmpty && _seeded) {
        if (_name.text.isEmpty) _name.text = next.name;
        if (_contact.text.isEmpty) _contact.text = next.contact;
        if (_address.text.isEmpty) _address.text = next.address;
      }
    });
    _seed(profile);
    final muted = context.mutedInkColor;
    final logoPath = profile.logoPath;
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: LabColors.marginRed),
              const SizedBox(width: 8),
              const Text(
                'report branding',
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Printed at the top of every PDF report. Stays on this device; '
            'leave it empty for plain Lab Wizard reports.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('profile-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Lab or institution name',
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('profile-contact'),
            controller: _contact,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Contact (email or phone)',
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('profile-address'),
            controller: _address,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Address'),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (logoPath != null && File(logoPath).existsSync())
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(logoPath),
                      key: const Key('profile-logo'),
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('profile-pick-logo'),
                onPressed: _busy ? null : _chooseLogo,
                icon: const Icon(Icons.image_outlined),
                label: Text(logoPath == null ? 'Add logo' : 'Change logo'),
              ),
              if (logoPath != null)
                TextButton(
                  key: const Key('profile-remove-logo'),
                  onPressed: _busy
                      ? null
                      : () => ref.read(labProfileProvider.notifier).clearLogo(),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
