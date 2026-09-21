import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/notebook_widgets.dart';
import 'lab_switcher_sheet.dart';
import 'organization_providers.dart';

class OrganizationCard extends ConsumerWidget {
  const OrganizationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLab = ref.watch(activeLabProvider);
    final isPersonal = activeLab == null;

    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_outlined, size: 20, color: context.inkColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'organization & labs',
                  style: TextStyle(
                    fontFamily: 'Caveat',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPersonal
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isPersonal ? 'Personal Mode' : activeLab.userRole.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPersonal
                        ? context.mutedInkColor
                        : Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPersonal
                ? 'Active workspace: Personal Lab\nYour inventory is stored privately in your personal lab notebook.'
                : 'Active workspace: ${activeLab.name}\nOrganization: ${activeLab.organizationName.isNotEmpty ? activeLab.organizationName : 'Shared Org'}\nRole: ${activeLab.userRole.label}',
            style: TextStyle(color: context.mutedInkColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showLabSwitcherSheet(context),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Switch active lab…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
