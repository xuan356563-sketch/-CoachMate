import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';

void main() {
  test('结构化处方可完整序列化且不包含动作与医疗字段', () {
    const String hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const String fragmentHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final AiTrainingPrescription prescription = AiTrainingPrescription.fromJson(
      <String, dynamic>{
        'cycle_focus': 'base',
        'progression_mode': 'conservative',
        'weekly_sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'training_type': 'strength',
            'duration_minutes': 45,
            'intensity_band': 'moderate',
            'focus_codes': <String>['movement_quality'],
          },
        ],
        'applied_skill': <String, dynamic>{
          'id': 'training-plan-builder',
          'version': '1.1.0',
          'display_name': '训练计划生成器',
          'source_sha256': hash,
          'runtime_sha256': hash,
          'fragment_sha256': fragmentHash,
          'coverage': 'marathon',
          'selection_reason': '主运动使用通用周期化规则，并叠加已审核专项片段',
        },
        'generation_meta': <String, dynamic>{
          'contract_version': 1,
          'client_context_digest': hash,
          'prompt_contract_version': 'training-prescription-v1',
          'model': 'deepseek-chat',
          'cache_hit': false,
          'token_usage': 321,
        },
        'selection_reason_code': 'generic_periodization_fallback',
      },
    );

    expect(
        prescription.weeklySessions.single.trainingType, TrainingType.strength);
    expect(prescription.skill.version, '1.1.0');
    expect(prescription.skill.fragmentSha256, fragmentHash);
    expect(prescription.generationMeta.clientContextDigest, hash);
    expect(prescription.toJson(), isNot(contains('exercise_id')));
    expect(prescription.toJson(), isNot(contains('medical_advice')));
    expect(
      AiTrainingPrescription.fromJson(prescription.toJson()).toJson(),
      prescription.toJson(),
    );
  });

  test('远程处方缺少版本、哈希或选择原因时严格拒绝', () {
    expect(
      () => AiTrainingPrescription.fromJson(<String, dynamic>{
        'cycle_focus': 'base',
        'progression_mode': 'conservative',
        'weekly_sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'training_type': 'strength',
            'duration_minutes': 45,
            'intensity_band': 'moderate',
            'focus_codes': <String>['movement_quality'],
          },
        ],
        'applied_skill': <String, dynamic>{'id': 'training-plan-builder'},
        'generation_meta': <String, dynamic>{'contract_version': 1},
      }),
      throwsFormatException,
    );
  });

  test('V2 处方解析知识版本、生成模式与双层缓存用量', () {
    const String hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final AiTrainingPrescription prescription = AiTrainingPrescription.fromJson(
      <String, dynamic>{
        'cycle_focus': 'base',
        'progression_mode': 'conservative',
        'weekly_sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'training_type': 'easy_run',
            'duration_minutes': 35,
            'intensity_band': 'easy',
            'focus_codes': <String>['aerobic_base'],
            'structure_profile': <String, dynamic>{
              'primary_dimension_codes': <String>['stability', 'breathing'],
              'touch_dimension_codes': <String>['strength'],
              'leg_element_codes': <String>[
                'foot_ankle',
                'eccentric_landing',
                'dynamic_stability',
              ],
            },
          },
        ],
        'applied_skill': <String, dynamic>{
          'id': 'training-plan-builder',
          'version': '1.1.0',
          'display_name': '训练计划生成器',
          'source_sha256': hash,
          'runtime_sha256': hash,
          'fragment_sha256': null,
          'coverage': 'general_fitness',
          'selection_reason': '主运动使用通用训练计划 Skill。',
        },
        'selection_reason_code': 'generic_periodization_fallback',
        'knowledge_citations': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'periodization',
            'type': 'principle',
            'title': '周期化',
            'source_label': 'TrainMate 内部训练原则',
            'source_section': '周期结构',
            'content_version': '2026.08.02-v2',
          },
        ],
        'generation_meta': <String, dynamic>{
          'contract_version': 2,
          'client_context_digest': hash,
          'prompt_contract_version': 'training-prescription-v2',
          'knowledge_snapshot_version': '2026.08.02-v2',
          'structure_policy_version': 'training-structure-v1',
          'generation_mode': 'local_template',
          'cache_hit': true,
          'app_cache_hit': true,
          'model': 'deterministic-template-v1',
          'input_tokens': 0,
          'output_tokens': 0,
          'prompt_cache_hit_tokens': 0,
          'prompt_cache_miss_tokens': 0,
        },
      },
    );

    expect(prescription.generationMeta.contractVersion, '2');
    expect(
      prescription.generationMeta.knowledgeSnapshotVersion,
      '2026.08.02-v2',
    );
    expect(prescription.generationMeta.generationMode, 'local_template');
    expect(
      prescription.generationMeta.structurePolicyVersion,
      trainingStructurePolicyVersion,
    );
    expect(prescription.generationMeta.appCacheHit, isTrue);
    expect(prescription.generationMeta.tokenUsage, 0);
    expect(prescription.knowledgeCitations.single.id, 'periodization');
    expect(
      prescription.knowledgeCitations.single.contentVersion,
      '2026.08.02-v2',
    );
    expect(
      prescription.weeklySessions.single.dimensionFocus.primary,
      <TrainingDimension>[
        TrainingDimension.stability,
        TrainingDimension.breathing,
      ],
    );
    expect(
      prescription.weeklySessions.single.legElements,
      contains(LegTrainingElement.eccentricLanding),
    );
  });

  test('V2 处方缺少知识引用时严格拒绝', () {
    const String hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(
      () => AiTrainingPrescription.fromJson(<String, dynamic>{
        'cycle_focus': 'base',
        'progression_mode': 'conservative',
        'weekly_sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'training_type': 'easy_run',
            'duration_minutes': 35,
            'intensity_band': 'easy',
            'focus_codes': <String>['aerobic_base'],
          },
        ],
        'applied_skill': <String, dynamic>{
          'id': 'training-plan-builder',
          'version': '1.1.0',
          'display_name': '训练计划生成器',
          'source_sha256': hash,
          'runtime_sha256': hash,
          'coverage': 'general_fitness',
          'selection_reason': '测试',
        },
        'selection_reason_code': 'generic_periodization_fallback',
        'generation_meta': <String, dynamic>{
          'contract_version': 2,
          'client_context_digest': hash,
          'prompt_contract_version': 'training-prescription-v2',
          'knowledge_snapshot_version': '2026.08.02-v2',
          'generation_mode': 'local_template',
          'cache_hit': false,
          'app_cache_hit': false,
          'model': 'deterministic-template-v1',
        },
      }),
      throwsFormatException,
    );
  });
}
