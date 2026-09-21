import 'package:flutter/material.dart';

enum OrganizationRole {
  owner,
  admin,
  member,
  viewer;

  static OrganizationRole fromString(String? role) =>
      switch (role?.toLowerCase()) {
        'owner' => OrganizationRole.owner,
        'admin' => OrganizationRole.admin,
        'viewer' => OrganizationRole.viewer,
        _ => OrganizationRole.member,
      };

  bool get canManageMembers => this == owner || this == admin;
  bool get canManageLabs => this == owner || this == admin;
  bool get canDeleteOrg => this == owner;

  String get label => switch (this) {
    owner => 'Owner',
    admin => 'Admin',
    member => 'Member',
    viewer => 'Viewer',
  };
}

enum LabRole {
  manager,
  member,
  viewer;

  static LabRole fromString(String? role) => switch (role?.toLowerCase()) {
    'manager' => LabRole.manager,
    'viewer' => LabRole.viewer,
    _ => LabRole.member,
  };

  bool get canManageInventory => this == manager || this == member;
  bool get canDeleteInventory => this == manager;
  bool get isReadOnly => this == viewer;

  String get label => switch (this) {
    manager => 'Lab Manager',
    member => 'Researcher / Member',
    viewer => 'Viewer (Read-only)',
  };
}

enum LabType {
  chemistry('chemistry', 'Chemistry', Icons.science_outlined),
  biology('biology', 'Biology', Icons.biotech_outlined),
  physics('physics', 'Physics', Icons.architecture_outlined),
  materials('materials', 'Materials Science', Icons.category_outlined),
  general('general', 'General Lab', Icons.domain_outlined);

  const LabType(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;

  static LabType fromCode(String? code) => switch (code?.toLowerCase()) {
    'chemistry' => chemistry,
    'biology' => biology,
    'physics' => physics,
    'materials' => materials,
    _ => general,
  };
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdBy,
    required this.createdAt,
    this.userRole = OrganizationRole.member,
  });

  final String id;
  final String name;
  final String slug;
  final String createdBy;
  final DateTime createdAt;
  final OrganizationRole userRole;

  factory Organization.fromMap(
    Map<String, dynamic> map, {
    OrganizationRole? userRole,
  }) {
    return Organization(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      slug: map['slug']?.toString() ?? '',
      createdBy: map['created_by']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      userRole:
          userRole ?? OrganizationRole.fromString(map['role']?.toString()),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'slug': slug,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'role': userRole.name,
  };
}

class Lab {
  const Lab({
    required this.id,
    required this.organizationId,
    required this.name,
    this.labType = LabType.general,
    this.roomNumber = '',
    required this.createdAt,
    this.userRole = LabRole.member,
    this.organizationName = '',
  });

  final String id;
  final String organizationId;
  final String name;
  final LabType labType;
  final String roomNumber;
  final DateTime createdAt;
  final LabRole userRole;
  final String organizationName;

  factory Lab.fromMap(
    Map<String, dynamic> map, {
    LabRole? userRole,
    String? orgName,
  }) {
    return Lab(
      id: map['id']?.toString() ?? '',
      organizationId: map['organization_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      labType: LabType.fromCode(map['lab_type']?.toString()),
      roomNumber: map['room_number']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      userRole: userRole ?? LabRole.fromString(map['role']?.toString()),
      organizationName: orgName ?? map['organization_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'organization_id': organizationId,
    'name': name,
    'lab_type': labType.code,
    'room_number': roomNumber,
    'created_at': createdAt.toIso8601String(),
    'role': userRole.name,
    'organization_name': organizationName,
  };
}

class OrganizationMember {
  const OrganizationMember({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.role,
    this.email = '',
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String userId;
  final OrganizationRole role;
  final String email;
  final DateTime createdAt;

  factory OrganizationMember.fromMap(Map<String, dynamic> map) {
    return OrganizationMember(
      id: map['id']?.toString() ?? '',
      organizationId: map['organization_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      role: OrganizationRole.fromString(map['role']?.toString()),
      email: map['email']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'organization_id': organizationId,
    'user_id': userId,
    'role': role.name,
    'email': email,
    'created_at': createdAt.toIso8601String(),
  };
}
