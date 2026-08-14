import '../../../data/models/profile_proposal.dart';

/// 只允许保存在设备加密草稿中的敏感资料。
///
/// 这里不保存联系方式，也不把年龄推导成生日；疼痛文本只截取明确的身体部位与症状，
/// 防止把同一句里的其他敏感内容带入正式档案。
class ProfileSensitiveDraft {
  final int? declaredAge;
  final double? heightCm;
  final double? weightKg;
  final String? painOrInjuryNote;

  const ProfileSensitiveDraft({
    this.declaredAge,
    this.heightCm,
    this.weightKg,
    this.painOrInjuryNote,
  });

  bool get isEmpty =>
      declaredAge == null &&
      heightCm == null &&
      weightKg == null &&
      painOrInjuryNote == null;

  ProfileSensitiveDraft merge(ProfileSensitiveDraft other) {
    return ProfileSensitiveDraft(
      declaredAge: other.declaredAge ?? declaredAge,
      heightCm: other.heightCm ?? heightCm,
      weightKg: other.weightKg ?? weightKg,
      painOrInjuryNote: other.painOrInjuryNote ?? painOrInjuryNote,
    );
  }

  factory ProfileSensitiveDraft.fromJson(Map<String, dynamic> json) {
    return ProfileSensitiveDraft(
      declaredAge: (json['declared_age'] as num?)?.toInt(),
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      painOrInjuryNote: json['pain_or_injury_note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'declared_age': declaredAge,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'pain_or_injury_note': painOrInjuryNote,
      };

  Map<String, String> get previewRows => <String, String>{
        if (declaredAge != null) '年龄': '$declaredAge 岁',
        if (heightCm != null) '身高': '${_numberLabel(heightCm!)} cm',
        if (weightKg != null) '体重': '${_numberLabel(weightKg!)} kg',
        if (painOrInjuryNote != null) '疼痛与伤病': painOrInjuryNote!,
      };
}

class ProfileFollowUpOption {
  final String value;
  final String label;

  const ProfileFollowUpOption(this.value, this.label);
}

class ProfileFollowUpQuestion {
  final String fieldCode;
  final String prompt;
  final List<ProfileFollowUpOption> options;

  const ProfileFollowUpQuestion({
    required this.fieldCode,
    required this.prompt,
    required this.options,
  });
}

class ProfileLocalExtraction {
  final Map<String, dynamic> knownFields;
  final List<String> unresolvedFieldCodes;
  final List<String> ambiguityFragments;
  final Set<String> sensitiveFieldCodes;
  final ProfileSensitiveDraft localSensitiveDraft;
  final List<ProfileFollowUpQuestion> followUpQuestions;

  const ProfileLocalExtraction({
    required this.knownFields,
    required this.unresolvedFieldCodes,
    required this.ambiguityFragments,
    required this.sensitiveFieldCodes,
    this.localSensitiveDraft = const ProfileSensitiveDraft(),
    this.followUpQuestions = const <ProfileFollowUpQuestion>[],
  });

  bool get requiresCloudProposal =>
      unresolvedFieldCodes.isNotEmpty && ambiguityFragments.isNotEmpty;

  ProfileProposalRequest toRequest({required String requestId}) {
    return ProfileProposalRequest(
      requestId: requestId,
      knownFields: Map<String, dynamic>.unmodifiable(knownFields),
      unresolvedFieldCodes:
          List<String>.unmodifiable(unresolvedFieldCodes.take(6)),
      ambiguityFragments: List<String>.unmodifiable(ambiguityFragments.take(5)),
    );
  }

  Map<String, dynamic> toRequestJson({required String requestId}) =>
      toRequest(requestId: requestId).toJson();
}

class ProfilePrivacyParser {
  const ProfilePrivacyParser();

  static const List<String> _requiredFields = <String>[
    'goal',
    'primary_sport',
    'experience_level',
    'weekly_training_days',
    'available_minutes',
    'equipment_access',
  ];

  ProfileLocalExtraction parse(String rawText) {
    final String normalized = rawText.trim();
    final Map<String, dynamic> knownFields = _extractKnownFields(normalized);
    final Set<String> sensitiveCodes = _detectSensitiveCodes(normalized);
    final List<String> unresolvedFields = _requiredFields
        .where((String field) => !knownFields.containsKey(field))
        .toList(growable: false);
    final List<String> ambiguityFragments = normalized
        .split(RegExp(r'[。！？!?；;\n]+'))
        .map((String fragment) => fragment.trim())
        .where((String fragment) => fragment.isNotEmpty)
        .where((String fragment) => _detectSensitiveCodes(fragment).isEmpty)
        .where((String fragment) => _extractKnownFields(fragment).isEmpty)
        .map(
          (String fragment) =>
              fragment.length <= 240 ? fragment : fragment.substring(0, 240),
        )
        .take(5)
        .toList(growable: false);
    return ProfileLocalExtraction(
      knownFields: knownFields,
      unresolvedFieldCodes: unresolvedFields,
      ambiguityFragments: ambiguityFragments,
      sensitiveFieldCodes: sensitiveCodes,
      localSensitiveDraft: _extractSensitiveDraft(normalized),
      followUpQuestions: unresolvedFields
          .map(_followUpQuestion)
          .whereType<ProfileFollowUpQuestion>()
          .take(5)
          .toList(growable: false),
    );
  }

  ProfileSensitiveDraft _extractSensitiveDraft(String text) {
    final RegExpMatch? ageMatch =
        RegExp(r'(?<!\d)(\d{1,3})\s*岁').firstMatch(text);
    final int? rawAge = int.tryParse(ageMatch?.group(1) ?? '');
    final int? declaredAge =
        rawAge != null && rawAge >= 1 && rawAge <= 120 ? rawAge : null;

    final RegExpMatch? heightMatch = RegExp(
      r'(?<!\d)(\d{2,3}(?:\.\d+)?)\s*(?:cm|厘米)',
      caseSensitive: false,
    ).firstMatch(text);
    final double? rawHeight = double.tryParse(heightMatch?.group(1) ?? '');
    final double? heightCm =
        rawHeight != null && rawHeight >= 80 && rawHeight <= 250
            ? rawHeight
            : null;

    final RegExpMatch? weightMatch = RegExp(
      r'(?<!\d)(\d{2,3}(?:\.\d+)?)\s*(?:kg|公斤|千克)',
      caseSensitive: false,
    ).firstMatch(text);
    final double? rawWeight = double.tryParse(weightMatch?.group(1) ?? '');
    final double? weightKg =
        rawWeight != null && rawWeight >= 20 && rawWeight <= 350
            ? rawWeight
            : null;

    final String? painNote = _extractPainOrInjuryNote(text);
    return ProfileSensitiveDraft(
      declaredAge: declaredAge,
      heightCm: heightCm,
      weightKg: weightKg,
      painOrInjuryNote: painNote,
    );
  }

  Map<String, dynamic> _extractKnownFields(String text) {
    final Map<String, dynamic> fields = <String, dynamic>{};
    final String lower = text.toLowerCase();

    if (RegExp(r'减脂|减肥').hasMatch(text)) {
      fields['goal'] = 'fat_loss';
    } else if (RegExp(r'增肌|力量提升|变强').hasMatch(text)) {
      fields['goal'] = 'strength';
    } else if (RegExp(r'备赛|比赛|马拉松').hasMatch(text)) {
      fields['goal'] = 'race_preparation';
    } else if (RegExp(r'耐力|长距离').hasMatch(text)) {
      fields['goal'] = 'endurance';
    } else if (RegExp(r'综合健身|基础体能|保持健康').hasMatch(text)) {
      fields['goal'] = 'general_fitness';
    }

    if (lower.contains('hyrox')) {
      fields['primary_sport'] = 'hyrox';
    } else if (RegExp(r'跑步|跑者|马拉松|越野跑').hasMatch(text)) {
      fields['primary_sport'] = 'running';
    } else if (RegExp(r'力量训练|举铁|增肌').hasMatch(text)) {
      fields['primary_sport'] = 'strength';
    } else if (RegExp(r'综合健身|基础体能').hasMatch(text)) {
      fields['primary_sport'] = 'general_fitness';
    }

    if (RegExp(r'新手|初学|刚开始|零基础').hasMatch(text)) {
      fields['experience_level'] = 'beginner';
    } else if (RegExp(r'进阶|有一定经验|规律训练').hasMatch(text)) {
      fields['experience_level'] = 'intermediate';
    } else if (RegExp(r'高阶|资深|多年系统训练').hasMatch(text)) {
      fields['experience_level'] = 'advanced';
    }

    final RegExpMatch? daysMatch =
        RegExp(r'每周\s*([1-7一二三四五六七])\s*(?:天|次)').firstMatch(text);
    if (daysMatch != null) {
      final int? days = _chineseDigit(daysMatch.group(1)!);
      if (days != null) fields['weekly_training_days'] = days;
    }

    final RegExpMatch? minutesMatch =
        RegExp(r'(?:每次|单次)?\s*(\d{2,3})\s*分钟').firstMatch(text);
    if (minutesMatch != null) {
      final int? minutes = int.tryParse(minutesMatch.group(1)!);
      if (minutes != null && minutes >= 15 && minutes <= 180) {
        fields['available_minutes'] = minutes;
      }
    }

    final List<String> equipment = <String>[
      if (RegExp(r'徒手|无器械').hasMatch(text)) 'bodyweight',
      if (text.contains('哑铃')) 'dumbbell',
      if (text.contains('杠铃')) 'barbell',
      if (text.contains('健身房')) 'gym',
      if (text.contains('跑步机')) 'treadmill',
      if (RegExp(r'户外|操场').hasMatch(text)) 'outdoor',
    ];
    if (equipment.isNotEmpty) {
      fields['equipment_access'] = equipment;
    }
    return fields;
  }

  Set<String> _detectSensitiveCodes(String text) {
    final Set<String> codes = <String>{};
    if (RegExp(r'(?:\d{1,3}|[一二三四五六七八九十百]+)\s*(?:多)?岁|年龄|生日').hasMatch(text)) {
      codes.add('age');
    }
    if (RegExp(
      r'体重|身高|体脂|公斤|kg|心率|hrv|睡眠',
      caseSensitive: false,
    ).hasMatch(text)) {
      codes.add('body_metrics');
    }
    if (RegExp(r'疼|痛|伤|膝|腰|肩|康复|慢病').hasMatch(text)) {
      codes.add('pain_or_injury');
    }
    if (RegExp(
      r'1[3-9]\d{9}|手机号|电话|邮箱|'
      r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    ).hasMatch(text)) {
      codes.add('contact');
    }
    return codes;
  }
}

ProfileFollowUpQuestion? _followUpQuestion(String fieldCode) {
  return switch (fieldCode) {
    'goal' => const ProfileFollowUpQuestion(
        fieldCode: 'goal',
        prompt: '你的主要训练目标是什么？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('fat_loss', '低冲击减脂'),
          ProfileFollowUpOption('strength', '力量与增肌'),
          ProfileFollowUpOption('endurance', '基础耐力'),
          ProfileFollowUpOption('race_preparation', '赛事备赛'),
          ProfileFollowUpOption('general_fitness', '综合健康'),
        ],
      ),
    'primary_sport' => const ProfileFollowUpQuestion(
        fieldCode: 'primary_sport',
        prompt: '你主要想练什么项目？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('running', '跑步'),
          ProfileFollowUpOption('strength', '力量'),
          ProfileFollowUpOption('hyrox', 'HYROX'),
          ProfileFollowUpOption('general_fitness', '综合健身'),
        ],
      ),
    'experience_level' => const ProfileFollowUpQuestion(
        fieldCode: 'experience_level',
        prompt: '你的训练经验如何？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('beginner', '初学'),
          ProfileFollowUpOption('intermediate', '有规律训练经验'),
          ProfileFollowUpOption('advanced', '多年系统训练'),
        ],
      ),
    'weekly_training_days' => const ProfileFollowUpQuestion(
        fieldCode: 'weekly_training_days',
        prompt: '每周通常能训练几天？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('2', '2 天'),
          ProfileFollowUpOption('3', '3 天'),
          ProfileFollowUpOption('4', '4 天'),
          ProfileFollowUpOption('5', '5 天'),
          ProfileFollowUpOption('6', '6 天'),
        ],
      ),
    'available_minutes' => const ProfileFollowUpQuestion(
        fieldCode: 'available_minutes',
        prompt: '单次通常有多长时间？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('20', '20 分钟'),
          ProfileFollowUpOption('30', '30 分钟'),
          ProfileFollowUpOption('45', '45 分钟'),
          ProfileFollowUpOption('60', '60 分钟'),
          ProfileFollowUpOption('90', '90 分钟'),
        ],
      ),
    'equipment_access' => const ProfileFollowUpQuestion(
        fieldCode: 'equipment_access',
        prompt: '你主要可以使用什么器械？',
        options: <ProfileFollowUpOption>[
          ProfileFollowUpOption('bodyweight', '无器械'),
          ProfileFollowUpOption('dumbbell', '家用哑铃'),
          ProfileFollowUpOption('gym', '健身房'),
          ProfileFollowUpOption('outdoor', '户外场地'),
        ],
      ),
    _ => null,
  };
}

String? _extractPainOrInjuryNote(String text) {
  final RegExp bodyPartSymptom = RegExp(
    r'(?:左|右|双侧)?(?:膝盖?|膝|腰背|腰|肩膀|肩|脚踝|踝|髋|颈|手腕|肘)'
    r'[^，。！？!?；;\n]{0,12}(?:疼|痛|受伤|伤|不适|康复)',
  );
  final RegExpMatch? match = bodyPartSymptom.firstMatch(text);
  if (match != null) return match.group(0)?.trim();
  if (RegExp(r'慢病|伤病|康复').hasMatch(text)) {
    return '已声明疼痛、伤病或康复情况，请在正式保存前逐项核对。';
  }
  return null;
}

String _numberLabel(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

int? _chineseDigit(String value) {
  return switch (value) {
    '一' => 1,
    '二' => 2,
    '三' => 3,
    '四' => 4,
    '五' => 5,
    '六' => 6,
    '七' => 7,
    _ => int.tryParse(value),
  };
}
