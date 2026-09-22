import 'dart:convert';

/// Optional branding printed on PDF reports (REPORT-06). Stored on the device
/// only; nothing here is sent to the server.
class LabProfile {
  const LabProfile({
    this.name = '',
    this.contact = '',
    this.address = '',
    this.logoPath,
  });

  factory LabProfile.decode(String? json) {
    if (json == null || json.isEmpty) return const LabProfile();
    try {
      final map = jsonDecode(json);
      if (map is! Map) return const LabProfile();
      return LabProfile(
        name: (map['name'] as String?) ?? '',
        contact: (map['contact'] as String?) ?? '',
        address: (map['address'] as String?) ?? '',
        logoPath: (map['logo_path'] as String?)?.trim().isEmpty ?? true
            ? null
            : map['logo_path'] as String,
      );
    } on FormatException {
      return const LabProfile();
    }
  }

  /// Lab or institution name, printed as the report title line.
  final String name;

  /// Free line such as an email address or phone number.
  final String contact;

  /// Postal address; line breaks are kept.
  final String address;

  /// Absolute path of a copied logo image on this device, if any.
  final String? logoPath;

  bool get isEmpty =>
      name.trim().isEmpty &&
      contact.trim().isEmpty &&
      address.trim().isEmpty &&
      logoPath == null;

  LabProfile copyWith({
    String? name,
    String? contact,
    String? address,
    String? logoPath,
    bool clearLogo = false,
  }) => LabProfile(
    name: name ?? this.name,
    contact: contact ?? this.contact,
    address: address ?? this.address,
    logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
  );

  String encode() => jsonEncode({
    'name': name,
    'contact': contact,
    'address': address,
    if (logoPath != null) 'logo_path': logoPath,
  });

  @override
  bool operator ==(Object other) =>
      other is LabProfile &&
      other.name == name &&
      other.contact == contact &&
      other.address == address &&
      other.logoPath == logoPath;

  @override
  int get hashCode => Object.hash(name, contact, address, logoPath);
}
