import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/features/organizations/domain/models.dart';
import 'package:lab_wizard/features/organizations/presentation/lab_switcher_sheet.dart';
import 'package:lab_wizard/features/organizations/presentation/organization_card.dart';
import 'package:lab_wizard/features/organizations/presentation/organization_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Organization domain models', () {
    test('OrganizationRole permissions and labels', () {
      expect(OrganizationRole.owner.canManageMembers, isTrue);
      expect(OrganizationRole.owner.canManageLabs, isTrue);
      expect(OrganizationRole.owner.canDeleteOrg, isTrue);
      expect(OrganizationRole.owner.label, 'Owner');

      expect(OrganizationRole.admin.canManageMembers, isTrue);
      expect(OrganizationRole.admin.canManageLabs, isTrue);
      expect(OrganizationRole.admin.canDeleteOrg, isFalse);
      expect(OrganizationRole.admin.label, 'Admin');

      expect(OrganizationRole.member.canManageMembers, isFalse);
      expect(OrganizationRole.member.canManageLabs, isFalse);
      expect(OrganizationRole.member.canDeleteOrg, isFalse);

      expect(OrganizationRole.viewer.canManageMembers, isFalse);
      expect(OrganizationRole.viewer.label, 'Viewer');

      expect(OrganizationRole.fromString('owner'), OrganizationRole.owner);
      expect(OrganizationRole.fromString('ADMIN'), OrganizationRole.admin);
      expect(OrganizationRole.fromString('unknown'), OrganizationRole.member);
    });

    test('LabRole permissions and labels', () {
      expect(LabRole.manager.canManageInventory, isTrue);
      expect(LabRole.manager.canDeleteInventory, isTrue);
      expect(LabRole.manager.isReadOnly, isFalse);
      expect(LabRole.manager.label, 'Lab Manager');

      expect(LabRole.member.canManageInventory, isTrue);
      expect(LabRole.member.canDeleteInventory, isFalse);
      expect(LabRole.member.isReadOnly, isFalse);

      expect(LabRole.viewer.canManageInventory, isFalse);
      expect(LabRole.viewer.canDeleteInventory, isFalse);
      expect(LabRole.viewer.isReadOnly, isTrue);
      expect(LabRole.viewer.label, contains('Read-only'));

      expect(LabRole.fromString('manager'), LabRole.manager);
      expect(LabRole.fromString('viewer'), LabRole.viewer);
      expect(LabRole.fromString('other'), LabRole.member);
    });

    test('LabType codes and icons', () {
      expect(LabType.fromCode('chemistry'), LabType.chemistry);
      expect(LabType.fromCode('biology'), LabType.biology);
      expect(LabType.fromCode('physics'), LabType.physics);
      expect(LabType.fromCode('materials'), LabType.materials);
      expect(LabType.fromCode('unknown'), LabType.general);
      expect(LabType.chemistry.label, 'Chemistry');
    });

    test('Organization round-trip', () {
      final now = DateTime(2026, 9, 21, 12, 0);
      final org = Organization(
        id: 'org-1',
        name: 'Alpha Bio Labs',
        slug: 'alpha-bio',
        createdBy: 'user-1',
        createdAt: now,
        userRole: OrganizationRole.owner,
      );

      final map = org.toMap();
      expect(map['id'], 'org-1');
      expect(map['name'], 'Alpha Bio Labs');
      expect(map['role'], 'owner');

      final parsed = Organization.fromMap(map);
      expect(parsed.id, org.id);
      expect(parsed.name, org.name);
      expect(parsed.userRole, OrganizationRole.owner);
    });

    test('Lab round-trip', () {
      final now = DateTime(2026, 9, 21, 12, 0);
      final lab = Lab(
        id: 'lab-1',
        organizationId: 'org-1',
        name: 'Organic Prep 101',
        labType: LabType.chemistry,
        roomNumber: 'Room 304',
        createdAt: now,
        userRole: LabRole.manager,
        organizationName: 'Alpha Bio Labs',
      );

      final map = lab.toMap();
      expect(map['id'], 'lab-1');
      expect(map['lab_type'], 'chemistry');
      expect(map['room_number'], 'Room 304');
      expect(map['role'], 'manager');

      final parsed = Lab.fromMap(map);
      expect(parsed.id, lab.id);
      expect(parsed.name, lab.name);
      expect(parsed.labType, LabType.chemistry);
      expect(parsed.userRole, LabRole.manager);
      expect(parsed.organizationName, 'Alpha Bio Labs');
    });

    test('OrganizationMember round-trip', () {
      final now = DateTime(2026, 9, 21, 12, 0);
      final member = OrganizationMember(
        id: 'mem-1',
        organizationId: 'org-1',
        userId: 'u-42',
        role: OrganizationRole.admin,
        email: 'scientist@lab.edu',
        createdAt: now,
      );

      final map = member.toMap();
      expect(map['id'], 'mem-1');
      expect(map['role'], 'admin');

      final parsed = OrganizationMember.fromMap(map);
      expect(parsed.id, member.id);
      expect(parsed.role, OrganizationRole.admin);
      expect(parsed.email, 'scientist@lab.edu');
    });
  });

  group('LocalDatabase multi-tenant cache isolation (v5)', () {
    late String dbPath;
    late LocalDatabase localDb;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('org_db_test_');
      dbPath = '${dir.path}/test_v5.db';
      localDb = LocalDatabase(factory: databaseFactoryFfi, path: dbPath);
    });

    tearDown(() async {
      await localDb.close();
    });

    test('Upgrades to version 5 and isolates cached items by labId', () async {
      final db = await localDb.database;
      expect(await db.getVersion(), 5);

      // Insert item into Lab 1
      await localDb.upsertRecord('user-1', 'chemical', {
        'id': 'c-1',
        'name': 'Ethanol',
        'lab_id': 'lab-1',
        'organization_id': 'org-1',
      });

      // Insert item into Lab 2
      await localDb.upsertRecord('user-1', 'chemical', {
        'id': 'c-2',
        'name': 'Methanol',
        'lab_id': 'lab-2',
        'organization_id': 'org-1',
      });

      // Insert item into Personal Lab (no lab_id)
      await localDb.upsertRecord('user-1', 'chemical', {
        'id': 'c-3',
        'name': 'Acetone',
      });

      // Query Lab 1 specifically
      final lab1Items = await localDb.loadRecords(
        'user-1',
        'chemical',
        labId: 'lab-1',
      );
      expect(lab1Items.length, 1);
      expect(lab1Items.first['name'], 'Ethanol');

      // Query Lab 2 specifically
      final lab2Items = await localDb.loadRecords(
        'user-1',
        'chemical',
        labId: 'lab-2',
      );
      expect(lab2Items.length, 1);
      expect(lab2Items.first['name'], 'Methanol');

      // Unscoped query returns all user items (backward compatibility)
      final allItems = await localDb.loadRecords('user-1', 'chemical');
      expect(allItems.length, 3);
    });
  });

  group('Organization UI widgets', () {
    testWidgets('OrganizationCard shows Personal Mode when activeLab is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLabProvider.overrideWith((ref) => ActiveLabNotifier(ref)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: OrganizationCard()),
            ),
          ),
        ),
      );

      expect(find.text('organization & labs'), findsOneWidget);
      expect(find.text('Personal Mode'), findsOneWidget);
      expect(find.textContaining('Personal Lab'), findsOneWidget);
      expect(find.text('Switch active lab…'), findsOneWidget);
    });

    testWidgets('OrganizationCard shows active team lab details', (
      tester,
    ) async {
      final testLab = Lab(
        id: 'lab-101',
        organizationId: 'org-1',
        name: 'Analytical Lab 3B',
        labType: LabType.chemistry,
        createdAt: DateTime(2026, 9, 21),
        userRole: LabRole.manager,
        organizationName: 'Department of Chemistry',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLabProvider.overrideWith((ref) {
              final notifier = ActiveLabNotifier(ref);
              notifier.state = testLab;
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: OrganizationCard()),
            ),
          ),
        ),
      );

      expect(find.text('organization & labs'), findsOneWidget);
      expect(find.text('Lab Manager'), findsOneWidget);
      expect(find.textContaining('Analytical Lab 3B'), findsOneWidget);
      expect(find.textContaining('Department of Chemistry'), findsOneWidget);
    });

    testWidgets('showLabSwitcherSheet allows selecting Personal Lab', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userLabsProvider.overrideWith(
              (ref) async => [
                Lab(
                  id: 'lab-1',
                  organizationId: 'org-1',
                  name: 'Biotech Lab',
                  labType: LabType.biology,
                  createdAt: DateTime(2026, 9, 21),
                  userRole: LabRole.member,
                  organizationName: 'Alpha Bio',
                ),
              ],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showLabSwitcherSheet(context),
                  child: const Text('Open Switcher'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Switcher'));
      await tester.pumpAndSettle();

      expect(find.text('switch active lab'), findsOneWidget);
      expect(find.text('Personal Lab'), findsOneWidget);
      expect(find.text('Biotech Lab'), findsOneWidget);
      expect(find.text('Create new organization…'), findsOneWidget);

      // Tap Personal Lab to select it
      await tester.tap(find.text('Personal Lab'));
      await tester.pumpAndSettle();

      // Sheet dismissed
      expect(find.text('switch active lab'), findsNothing);
    });
  });
}
