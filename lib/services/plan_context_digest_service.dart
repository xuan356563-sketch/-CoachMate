import 'dart:convert';

import '../data/models/race.dart';
import '../data/models/user_profile.dart';

/// 只对允许发往处方接口的枚举化字段计算稳定 SHA-256。
class PlanContextDigestService {
  const PlanContextDigestService();

  /// 对任意由 JSON 基础类型组成的值计算规范化摘要。
  ///
  /// Coach 的 Dart/Python 双端契约复用这一实现，避免同一份结构化事实因
  /// Map 插入顺序不同而产生不同摘要。
  String buildCanonicalDigest(Object? value) {
    return _sha256Hex(utf8.encode(jsonEncode(_canonicalize(value))));
  }

  /// 网络摘要：仅对实际 request context 的规范 JSON 计算。
  String buildRequestContextDigest(Map<String, dynamic> requestContext) {
    return buildCanonicalDigest(requestContext);
  }

  /// 本地陈旧判定指纹：不得当作网络 client_context_digest。
  String buildLocalFingerprint({
    required UserProfile profile,
    required DateTime startsOn,
    RacePlan? race,
    String? activeVersionId,
  }) {
    final Map<String, dynamic> values = _localFingerprintValues(
      profile: profile,
      startsOn: startsOn,
      race: race,
      activeVersionId: activeVersionId,
    );
    return buildCanonicalDigest(values);
  }

  @Deprecated('请使用 buildLocalFingerprint 或 buildRequestContextDigest')
  String build({
    required UserProfile profile,
    required DateTime startsOn,
    RacePlan? race,
  }) {
    return buildLocalFingerprint(
      profile: profile,
      startsOn: startsOn,
      race: race,
    );
  }

  Map<String, dynamic> _localFingerprintValues({
    required UserProfile profile,
    required DateTime startsOn,
    required RacePlan? race,
    required String? activeVersionId,
  }) {
    final MainSport primarySport = profile.mainSports.isEmpty
        ? MainSport.generalFitness
        : profile.mainSports.first;
    final MainSport? secondarySport =
        profile.mainSports.length > 1 && profile.mainSports[1] != primarySport
            ? profile.mainSports[1]
            : null;
    final DateTime start =
        DateTime(startsOn.year, startsOn.month, startsOn.day);
    final int? daysUntilRace = race == null
        ? null
        : DateTime(race.raceDate.year, race.raceDate.month, race.raceDate.day)
            .difference(start)
            .inDays;
    return <String, dynamic>{
      'contract_version': 1,
      'primary_sport': primarySport.jsonValue,
      'secondary_sport': secondarySport?.jsonValue,
      'training_goal': profile.trainingGoal.trim(),
      'experience_level': profile.trainingExperienceLevel.jsonValue,
      // 性别在用户同意后才参与处方请求，改动（含撤回同意）应让既有计划判定为陈旧。
      // 走和请求体同一个入口，未同意或 other/unknown 时为 null。
      'biological_sex': profile.aiPlanningBiologicalSexCode,
      'weekly_training_days': profile.weeklyTrainingDays.clamp(1, 6),
      'available_minutes': profile.dailyAvailableMinutes,
      'equipment_access': profile.equipmentAccessType.jsonValue,
      'race_type': race?.type.jsonValue,
      'days_until_race': daysUntilRace,
      'starts_on': _dateLabel(start),
      'active_version_id': activeVersionId,
    };
  }

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, dynamic>{
      for (final String key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

String _sha256Hex(List<int> input) {
  const List<int> constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final List<int> bytes = List<int>.from(input)..add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  final int bitLength = input.length * 8;
  for (int shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }

  final List<int> hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  for (int offset = 0; offset < bytes.length; offset += 64) {
    final List<int> words = List<int>.filled(64, 0);
    for (int index = 0; index < 16; index += 1) {
      final int base = offset + index * 4;
      words[index] = ((bytes[base] << 24) |
              (bytes[base + 1] << 16) |
              (bytes[base + 2] << 8) |
              bytes[base + 3]) &
          0xffffffff;
    }
    for (int index = 16; index < 64; index += 1) {
      final int s0 = _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final int s1 = _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    int a = hash[0];
    int b = hash[1];
    int c = hash[2];
    int d = hash[3];
    int e = hash[4];
    int f = hash[5];
    int g = hash[6];
    int h = hash[7];
    for (int index = 0; index < 64; index += 1) {
      final int sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final int choice = (e & f) ^ ((~e) & g);
      final int temp1 =
          (h + sum1 + choice + constants[index] + words[index]) & 0xffffffff;
      final int sum0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (sum0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }
  return hash
      .map((int value) => value.toRadixString(16).padLeft(8, '0'))
      .join();
}

int _rotateRight(int value, int bits) =>
    ((value >> bits) | (value << (32 - bits))) & 0xffffffff;
