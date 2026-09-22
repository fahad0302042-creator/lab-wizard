import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

class OrganizationRepository {
  OrganizationRepository({required this.client});

  final SupabaseClient client;

  /// Loads organizations the signed-in user belongs to.
  /// Returns an empty list safely if the schema migration has not been run.
  Future<List<Organization>> loadUserOrganizations() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];

    try {
      final memberships = await client
          .from('organization_members')
          .select('role, organizations(*)')
          .eq('user_id', user.id);

      final result = <Organization>[];
      for (final row in memberships as List) {
        if (row is! Map<String, dynamic>) continue;
        final orgMap = row['organizations'];
        if (orgMap is! Map<String, dynamic>) continue;
        final role = OrganizationRole.fromString(row['role']?.toString());
        result.add(Organization.fromMap(orgMap, userRole: role));
      }
      return result;
    } catch (_) {
      // 010 migration not installed or offline; fallback cleanly.
      return const [];
    }
  }

  /// Loads labs the signed-in user belongs to across their organizations.
  Future<List<Lab>> loadUserLabs() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];

    try {
      final memberships = await client
          .from('lab_members')
          .select('role, labs(*, organizations(name))')
          .eq('user_id', user.id);

      final result = <Lab>[];
      for (final row in memberships as List) {
        if (row is! Map<String, dynamic>) continue;
        final labMap = row['labs'];
        if (labMap is! Map<String, dynamic>) continue;
        final orgMap = labMap['organizations'];
        final orgName = (orgMap is Map) ? orgMap['name']?.toString() : null;
        final role = LabRole.fromString(row['role']?.toString());
        result.add(Lab.fromMap(labMap, userRole: role, orgName: orgName));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Creates a new organization with a default lab in one PostgreSQL transaction.
  Future<String?> createOrganization({
    required String name,
    required String slug,
    String defaultLabName = 'Main Lab',
    String labType = 'general',
  }) async {
    try {
      final response = await client.rpc(
        'create_organization_with_lab',
        params: {
          'p_name': name.trim(),
          'p_slug': slug.trim().toLowerCase(),
          'p_default_lab_name': defaultLabName.trim(),
          'p_lab_type': labType,
        },
      );
      return response?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Creates a lab inside an existing organization.
  Future<Lab?> createLab({
    required String organizationId,
    required String name,
    LabType labType = LabType.general,
    String roomNumber = '',
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      final labRow = await client
          .from('labs')
          .insert({
            'organization_id': organizationId,
            'name': name.trim(),
            'lab_type': labType.code,
            'room_number': roomNumber.trim(),
          })
          .select()
          .single();

      final lab = Lab.fromMap(labRow, userRole: LabRole.manager);

      // Add user as manager
      await client.from('lab_members').insert({
        'lab_id': lab.id,
        'user_id': user.id,
        'role': 'manager',
      });

      return lab;
    } catch (_) {
      return null;
    }
  }
}
