import 'dart:convert';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';

/// 将现有用户资料文档投影为 SQLite 运动员根记录。
class AthleteProfileProjection {
  const AthleteProfileProjection._();

  static Map<String, Object?> fromLegacyDocument(
    Map<String, dynamic>? document, {
    required DateTime projectedAt,
  }) {
    final UserProfile profile = _readProfile(document);
    if (profile.id.trim().isEmpty || profile.name.trim().isEmpty) {
      throw const FormatException('用户资料缺少运动员 ID 或名称');
    }
    final Map<String, dynamic> payload = profile.toJson();
    return <String, Object?>{
      'id': profile.id,
      'name': profile.name,
      'age': profile.age > 0 ? profile.age : null,
      'birth_date': profile.birthDate == null
          ? null
          : _dateKey(profile.birthDate!),
      'biological_sex': profile.gender.jsonValue,
      'height_cm': profile.heightCm > 0 ? profile.heightCm : null,
      'weight_kg': profile.weightKg > 0 ? profile.weightKg : null,
      'experience_level': profile.workerProfileType.jsonValue,
      'payload_json': jsonEncode(payload),
      'created_at': profile.createdAt.toUtc().toIso8601String(),
      'updated_at': projectedAt.toUtc().toIso8601String(),
    };
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static UserProfile _readProfile(Map<String, dynamic>? document) {
    if (document == null) {
      return InMemoryUserProfileRepository.defaultProfile;
    }
    final Object? rawProfile = document['profile'];
    if (rawProfile == null && document['profileCompleted'] != true) {
      return InMemoryUserProfileRepository.defaultProfile;
    }
    if (rawProfile is! Map) {
      throw const FormatException('用户资料文档格式无效');
    }
    final Map<String, dynamic> json = <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in rawProfile.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final UserProfile profile = UserProfile.fromJson(json);
    if (profile.createdAt.millisecondsSinceEpoch == 0 ||
        profile.updatedAt.millisecondsSinceEpoch == 0) {
      throw const FormatException('用户资料时间字段无效');
    }
    return profile;
  }
}
