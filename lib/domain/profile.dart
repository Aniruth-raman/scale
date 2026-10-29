import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// A local household member. There is no account and no server-side profile.
@immutable
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.heightCm,
    this.sex,
    this.birthYear,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int? heightCm;
  final String? sex;
  final int? birthYear;
  final DateTime createdAt;

  int? get age => birthYear == null ? null : DateTime.now().year - birthYear!;
}

/// Household profile storage. Active-profile selection is a local setting.
abstract class ProfileRepository {
  Future<List<Profile>> getAll();
  Future<Profile> ensureActive();
  Future<void> save(Profile profile);
  Future<void> delete(String id);
  Future<String?> activeId();
  Future<void> setActive(String id);
}

const Uuid _uuid = Uuid();

String newProfileId() => _uuid.v4();
