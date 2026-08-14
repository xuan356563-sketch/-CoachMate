import '../domain/first_run_models.dart';

class PersonalProfileParseResult {
  const PersonalProfileParseResult({
    required this.profile,
    required this.missingFields,
  });

  final PersonalProfileDraft profile;
  final List<String> missingFields;

  bool get rawTextRetained => false;
}

class PersonalProfileLocalParser {
  const PersonalProfileLocalParser();

  PersonalProfileParseResult parse(String rawText) {
    final String text = rawText.trim();
    final String nickname =
        RegExp(r'(?:我叫|昵称(?:是|叫)?)\s*([\u4e00-\u9fa5A-Za-z0-9_]{1,12})')
                .firstMatch(text)
                ?.group(1) ??
            '';
    final int age = int.tryParse(
          RegExp(r'(\d{1,3})\s*岁').firstMatch(text)?.group(1) ?? '',
        ) ??
        0;
    final double? height = double.tryParse(
      RegExp(r'(\d{3}(?:\.\d+)?)\s*(?:厘米|cm)').firstMatch(text)?.group(1) ?? '',
    );
    final double? weight = double.tryParse(
      RegExp(r'(\d{2,3}(?:\.\d+)?)\s*(?:公斤|千克|kg)')
              .firstMatch(text)
              ?.group(1) ??
          '',
    );
    final String gender =
        RegExp(r'(?:^|[，,。\s])男(?:性)?(?:[，,。\s]|$)').hasMatch(text)
            ? 'male'
            : RegExp(r'(?:^|[，,。\s])女(?:性)?(?:[，,。\s]|$)').hasMatch(text)
                ? 'female'
                : 'unknown';
    final String goal = RegExp(r'减脂|减肥').hasMatch(text)
        ? 'fat_loss'
        : RegExp(r'增肌|力量').hasMatch(text)
            ? 'strength'
            : RegExp(r'跑步|马拉松|备赛').hasMatch(text)
                ? 'race_preparation'
                : 'general_fitness';
    final String worker = RegExp(r'办公室|久坐|文员|程序员').hasMatch(text)
        ? 'sedentary_office'
        : RegExp(r'倒班|夜班').hasMatch(text)
            ? 'shift_worker'
            : RegExp(r'学生').hasMatch(text)
                ? 'student'
                : 'other';
    final List<StructuredInjuryProfile> injuries = _extractInjuries(text);
    final PersonalProfileDraft profile = PersonalProfileDraft(
      nickname: nickname,
      gender: gender,
      declaredAge: age,
      heightCm: height,
      weightKg: weight,
      workerProfileType: worker,
      workScheduleType:
          worker == 'shift_worker' ? 'rotating_shift' : 'regular_office',
      trainingGoal: goal,
      mainSports: RegExp(r'跑步|马拉松').hasMatch(text)
          ? const <String>['running']
          : const <String>[],
      trainingExperienceLevel:
          RegExp(r'进阶|规律训练|多年').hasMatch(text) ? 'intermediate' : 'beginner',
      injuries: injuries,
    );
    return PersonalProfileParseResult(
      profile: profile,
      missingFields: <String>[
        if (nickname.isEmpty) 'nickname',
        if (gender == 'unknown') 'gender',
        if (age == 0) 'declared_age',
      ],
    );
  }

  List<StructuredInjuryProfile> _extractInjuries(String text) {
    if (!RegExp(r'伤|疼|痛|不适|不舒服|受限').hasMatch(text)) {
      return const <StructuredInjuryProfile>[];
    }
    String region = 'other';
    if (RegExp(r'右膝').hasMatch(text)) {
      region = 'right_knee';
    } else if (RegExp(r'左膝').hasMatch(text)) {
      region = 'left_knee';
    } else if (RegExp(r'膝').hasMatch(text)) {
      region = 'knee';
    } else if (RegExp(r'腰').hasMatch(text)) {
      region = 'lower_back';
    } else if (RegExp(r'肩').hasMatch(text)) {
      region = 'shoulder';
    }
    final String state = RegExp(r'以前|曾经|恢复').hasMatch(text)
        ? 'recovered'
        : RegExp(r'偶尔|偶有').hasMatch(text)
            ? 'occasional_discomfort'
            : RegExp(r'受限|不能').hasMatch(text)
                ? 'currently_limited'
                : 'uncertain';
    final String limiting = RegExp(r'跑').hasMatch(text)
        ? 'run'
        : RegExp(r'跳').hasMatch(text)
            ? 'jump'
            : RegExp(r'蹲').hasMatch(text)
                ? 'squat'
                : 'other';
    final String note = text.length <= 40 ? text : '${text.substring(0, 39)}…';
    return <StructuredInjuryProfile>[
      StructuredInjuryProfile(
        bodyRegion: region,
        state: state,
        limitingActivity: limiting,
        confirmedNote: note,
      ),
    ];
  }
}
