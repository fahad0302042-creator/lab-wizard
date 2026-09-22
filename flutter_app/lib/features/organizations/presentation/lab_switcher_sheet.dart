import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../inventory/presentation/inventory_sheets.dart';
import 'organization_providers.dart';

Future<void> showLabSwitcherSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const NotebookSheetFrame(
      maxHeightFactor: 0.85,
      child: _LabSwitcherContent(),
    ),
  );
}

class _LabSwitcherContent extends ConsumerWidget {
  const _LabSwitcherContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLab = ref.watch(activeLabProvider);
    final labsAsync = ref.watch(userLabsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: context.mutedInkColor.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Text(
          'switch active lab',
          style: TextStyle(
            fontFamily: 'Caveat',
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select which lab notebook to view and manage. Personal items remain private.',
          style: TextStyle(color: context.mutedInkColor, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // 1. Personal Lab option (always available)
        _LabListTile(
          title: 'Personal Lab',
          subtitle: 'Your private inventory notebook',
          icon: Icons.person_pin_outlined,
          isSelected: activeLab == null,
          onTap: () async {
            await ref.read(activeLabProvider.notifier).selectLab(null);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        const Divider(height: 24),
        labsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Cloud organization features require migration 010.',
              style: TextStyle(color: context.mutedInkColor, fontSize: 12),
            ),
          ),
          data: (labs) {
            if (labs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No team organizations found. You are working in your private lab.',
                  style: TextStyle(color: context.mutedInkColor, fontSize: 13),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final lab in labs)
                  _LabListTile(
                    title: lab.name,
                    subtitle:
                        '${lab.organizationName.isNotEmpty ? '${lab.organizationName} · ' : ''}${lab.userRole.label}${lab.roomNumber.isNotEmpty ? ' · Room ${lab.roomNumber}' : ''}',
                    icon: lab.labType.icon,
                    isSelected: activeLab?.id == lab.id,
                    badgeText: lab.userRole.label,
                    onTap: () async {
                      await ref.read(activeLabProvider.notifier).selectLab(lab);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _showCreateOrgDialog(context, ref),
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Create new organization…'),
        ),
      ],
    );
  }

  void _showCreateOrgDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final slugController = TextEditingController();
    final labController = TextEditingController(text: 'Main Lab');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.paperColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.inkColor.withValues(alpha: 0.2)),
        ),
        title: const Text('Create organization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Organization name',
                hintText: 'e.g. Acme Research Labs',
              ),
              onChanged: (val) {
                if (slugController.text.isEmpty ||
                    slugController.text ==
                        _slugify(
                          nameController.text.substring(
                            0,
                            nameController.text.length - 1,
                          ),
                        )) {
                  slugController.text = _slugify(val);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: slugController,
              decoration: const InputDecoration(
                labelText: 'Organization slug',
                hintText: 'e.g. acme-research',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: labController,
              decoration: const InputDecoration(
                labelText: 'Initial lab name',
                hintText: 'e.g. Main Chemistry Lab',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final slug = slugController.text.trim();
              final labName = labController.text.trim();
              if (name.isEmpty || slug.isEmpty) {
                return;
              }

              Navigator.of(dialogCtx).pop();
              final repo = ref.read(organizationRepositoryProvider);
              final orgId = await repo.createOrganization(
                name: name,
                slug: slug,
                defaultLabName: labName.isNotEmpty ? labName : 'Main Lab',
              );

              if (orgId != null) {
                ref.invalidate(userOrganizationsProvider);
                ref.invalidate(userLabsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created organization "$name"')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  static String _slugify(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

class _LabListTile extends StatelessWidget {
  const _LabListTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badgeText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: 0.35)
            : context.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : context.inkColor.withValues(alpha: 0.15),
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Icon(
            icon,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: isSelected
              ? const Icon(Icons.check_circle, size: 20)
              : const Icon(Icons.chevron_right, size: 18),
          onTap: onTap,
        ),
      ),
    );
  }
}
