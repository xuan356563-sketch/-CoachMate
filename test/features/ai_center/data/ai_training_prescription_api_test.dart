import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trainflow_ai/features/ai_center/data/ai_api.dart';
import 'package:trainflow_ai/features/ai_center/data/training_prescription_api_models.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';

class _TokenStore implements SessionTokenStore {
  @override
  String? accessToken = 'access-token';

  @override
  Future<void> clear() async => accessToken = null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> updateAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
  }
}

void main() {
  test('训练处方请求只发送白名单字段并解析固定 Artifact', () async {
    final MockClient httpClient = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/training-prescriptions');
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, <String>{
        'contract_version',
        'client_context_digest',
        'context',
        'force',
      });
      final Map<String, dynamic> context =
          body['context']! as Map<String, dynamic>;
      expect(context.keys, <String>{
        'goal',
        'primary_sport',
        'secondary_sport',
        'experience_level',
        'weekly_training_days',
        'available_minutes',
        'equipment_access',
        'race_type',
        'days_until_race',
      });
      final String encoded = jsonEncode(body);
      expect(encoded, isNot(contains('name')));
      expect(encoded, isNot(contains('age')));
      expect(encoded, isNot(contains('injury')));
      expect(encoded, isNot(contains('clearance')));
      expect(encoded, isNot(contains('pain')));
      expect(encoded, isNot(contains('health')));
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 'artifact-1',
          'capability': 'trainer',
          'artifact_type': 'training_prescription_v1',
          'schema_version': 1,
          'decision_status': 'pending',
          'context_digest': _digestA,
          'payload': <String, dynamic>{
            'cycle_focus': 'base',
            'weekly_sessions': <Map<String, dynamic>>[
              <String, dynamic>{
                'training_type': 'strength',
                'duration_minutes': 45,
                'intensity_band': 'moderate',
                'focus_codes': <String>['full_body_strength'],
              },
            ],
            'progression_mode': 'conservative',
            'applied_skill': <String, dynamic>{
              'id': 'training-plan-builder',
              'version': '1.0.0',
              'display_name': '训练计划生成器',
              'source_sha256': _digestB,
              'runtime_sha256': _digestC,
              'fragment_sha256': null,
              'coverage': 'general_fitness',
            },
            'selection_reason': '主运动使用通用训练计划 Skill。',
            'selection_reason_code': 'generic_periodization_fallback',
            'generation_meta': <String, dynamic>{
              'contract_version': 1,
              'client_context_digest': _digestA,
              'prompt_contract_version': 'training-prescription-v1',
              'cache_hit': false,
              'input_tokens': 10,
              'output_tokens': 20,
              'model': 'deepseek-chat',
            },
          },
          'warnings': <String>[],
          'provider': 'deepseek',
          'model': 'deepseek-chat',
          'generated_at': '2026-07-17T00:00:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: httpClient,
        tokenStore: _TokenStore(),
      ),
    );

    final artifact = await api.generateTrainingPrescription(
      TrainingPrescriptionRequest(
        contractVersion: 1,
        clientContextDigest: _digestA,
        context: const TrainingPrescriptionRequestContext(
          goal: 'race_preparation',
          primarySport: 'hyrox',
          secondarySport: 'marathon',
          experienceLevel: 'intermediate',
          weeklyTrainingDays: 6,
          availableMinutes: 45,
          equipmentAccess: <String>['bodyweight', 'dumbbell'],
          raceType: 'hyrox',
          daysUntilRace: 90,
        ),
      ),
    );

    expect(artifact.trainingPrescription?.skill.id, 'training-plan-builder');
    expect(artifact.trainingPrescription?.weeklySessions, hasLength(1));
  });

  test('能力接口读取功能开关和 Skill 双哈希', () async {
    final MockClient httpClient = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/training-prescriptions/capabilities');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'enabled': true,
          'contract_version': 1,
          'skills': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'training-plan-builder',
              'version': '1.0.0',
              'display_name': '训练计划生成器',
              'sports': <String>['general_fitness', 'hyrox'],
              'source_sha256': _digestB,
              'runtime_sha256': _digestC,
              'fragment_sha256': <String, String>{
                'hyrox': _digestA,
              },
            },
          ],
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: httpClient,
        tokenStore: _TokenStore(),
      ),
    );

    final capabilities = await api.trainingPrescriptionCapabilities();

    expect(capabilities.enabled, isTrue);
    expect(capabilities.skills.single.version, '1.0.0');
    expect(capabilities.skills.single.runtimeSha256, hasLength(64));
    expect(capabilities.skills.single.fragmentSha256['hyrox'], _digestA);
  });

  test('能力开启但 Skill 哈希缺失时按服务不可用处理', () async {
    final MockClient httpClient = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'enabled': true,
          'contract_version': 1,
          'skills': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'training-plan-builder',
              'version': '1.0.0',
              'display_name': '训练计划生成器',
              'sports': <String>['general_fitness'],
              'source_sha256': '',
              'runtime_sha256': '',
            },
          ],
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: httpClient,
        tokenStore: _TokenStore(),
      ),
    );

    expect(
      api.trainingPrescriptionCapabilities(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.code,
          'code',
          'training_plan_skill_unavailable',
        ),
      ),
    );
  });

  test('能力契约版本或 Skill 语义版本非法时返回中文不可用错误', () async {
    final List<Map<String, dynamic>> invalidResponses = <Map<String, dynamic>>[
      <String, dynamic>{
        'enabled': false,
        'contract_version': 0,
        'skills': <Map<String, dynamic>>[],
      },
      <String, dynamic>{
        'enabled': true,
        'contract_version': 1,
        'skills': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'training-plan-builder',
            'version': '版本一',
            'display_name': '训练计划生成器',
            'sports': <String>['general_fitness'],
            'source_sha256': _digestB,
            'runtime_sha256': _digestC,
          },
        ],
      },
    ];

    for (final Map<String, dynamic> invalid in invalidResponses) {
      final AiApi api = AiApi(
        AuthenticatedApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(invalid),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            ),
          ),
          tokenStore: _TokenStore(),
        ),
      );

      await expectLater(
        api.trainingPrescriptionCapabilities(),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.code,
                'code',
                'training_plan_skill_unavailable',
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('现有计划不会改变'),
              ),
        ),
      );
    }
  });

  test('V2 目录提供七种自动模式且处方请求不含敏感档案字段', () async {
    final MockClient httpClient = MockClient((http.Request request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/v1/knowledge/catalog');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'version': '2026.08.02-v2',
            'population_templates': _populationTemplates,
            'principles': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'periodization', 'status': 'verified'},
            ],
            'training_templates': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'low_impact_fat_loss_3d',
                'status': 'verified',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      expect(request.url.path, '/v2/ai/training-prescriptions');
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['contract_version'], 2);
      expect(body['population_template_id'], 'low_impact_fat_loss');
      expect(body['knowledge_snapshot_version'], '2026.08.02-v2');
      final Map<String, dynamic> context =
          body['context']! as Map<String, dynamic>;
      expect(context.keys, <String>{
        'goal',
        'primary_sport',
        'experience_level',
        'weekly_training_days',
        'available_minutes',
        'equipment_access',
      });
      final String encoded = jsonEncode(body);
      for (final String forbidden in <String>[
        'height',
        'injury',
        'pain',
        'phone',
        'email',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }
      return http.Response(
        jsonEncode(_v2Artifact),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: httpClient,
        tokenStore: _TokenStore(),
      ),
    );

    final KnowledgeCatalogSummary catalog = await api.knowledgeCatalog();
    final artifact = await api.generateTrainingPrescriptionV2(
      TrainingPrescriptionV2Request(
        clientContextDigest: _digestA,
        populationTemplateId: 'low_impact_fat_loss',
        knowledgeSnapshotVersion: catalog.version,
        context: const TrainingPrescriptionRequestContext(
          goal: 'fat_loss',
          primarySport: 'general_fitness',
          secondarySport: null,
          experienceLevel: 'beginner',
          weeklyTrainingDays: 3,
          availableMinutes: 40,
          equipmentAccess: <String>['bodyweight', 'dumbbell'],
          raceType: null,
          daysUntilRace: null,
        ),
      ),
    );

    expect(catalog.populationTemplates, hasLength(7));
    expect(catalog.allPopulationTemplates, hasLength(8));
    expect(
      catalog.allPopulationTemplates.singleWhere(
        (PopulationTemplateOption item) =>
            item.id == 'return_to_training_guarded',
      ).automaticPlanAllowed,
      isFalse,
    );
    expect(artifact.artifactType, 'training_prescription_v2');
    expect(
      artifact.trainingPrescription?.generationMeta.generationMode,
      'local_template',
    );
  });
}

const List<Map<String, dynamic>> _populationTemplates = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'sedentary_beginner',
    'title': '久坐办公初学者',
    'automatic_plan_allowed': true,
    'progression_mode': 'conservative',
  },
  <String, dynamic>{
    'id': 'low_impact_fat_loss',
    'title': '低冲击减脂',
    'automatic_plan_allowed': true,
    'progression_mode': 'conservative',
  },
  <String, dynamic>{
    'id': 'strength_progression',
    'title': '力量与增肌进阶',
    'automatic_plan_allowed': true,
    'progression_mode': 'balanced',
  },
  <String, dynamic>{
    'id': 'running_entry_or_race',
    'title': '跑步入门或备赛',
    'automatic_plan_allowed': true,
    'progression_mode': 'balanced',
  },
  <String, dynamic>{
    'id': 'hyrox_hybrid',
    'title': 'HYROX 混合体能',
    'automatic_plan_allowed': true,
    'progression_mode': 'balanced',
  },
  <String, dynamic>{
    'id': 'older_adult_foundation',
    'title': '老年基础低冲击',
    'automatic_plan_allowed': true,
    'progression_mode': 'conservative',
  },
  <String, dynamic>{
    'id': 'shift_worker_flexible',
    'title': '轮班人群弹性日程',
    'automatic_plan_allowed': true,
    'progression_mode': 'conservative',
  },
  <String, dynamic>{
    'id': 'return_to_training_guarded',
    'title': '伤病后重返训练',
    'automatic_plan_allowed': false,
    'progression_mode': 'conservative',
  },
];

const Map<String, dynamic> _v2Artifact = <String, dynamic>{
  'id': 'artifact-v2',
  'capability': 'trainer',
  'artifact_type': 'training_prescription_v2',
  'schema_version': 2,
  'decision_status': 'pending',
  'context_digest': _digestB,
  'payload': <String, dynamic>{
    'population_template_id': 'low_impact_fat_loss',
    'cycle_focus': 'base',
    'weekly_sessions': <Map<String, dynamic>>[
      <String, dynamic>{
        'training_type': 'easy_run',
        'duration_minutes': 40,
        'intensity_band': 'easy',
        'focus_codes': <String>['aerobic_base'],
      },
    ],
    'progression_mode': 'conservative',
    'applied_skill': <String, dynamic>{
      'id': 'training-plan-builder',
      'version': '1.0.0',
      'display_name': '训练计划生成器',
      'source_sha256': _digestB,
      'runtime_sha256': _digestC,
      'fragment_sha256': null,
      'coverage': 'general_fitness',
    },
    'selection_reason': '主运动使用通用训练计划 Skill。',
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
      'client_context_digest': _digestA,
      'prompt_contract_version': 'training-prescription-v2',
      'knowledge_snapshot_version': '2026.08.02-v2',
      'generation_mode': 'local_template',
      'cache_hit': false,
      'app_cache_hit': false,
      'model': 'deterministic-template-v1',
      'input_tokens': 0,
      'output_tokens': 0,
      'prompt_cache_hit_tokens': 0,
      'prompt_cache_miss_tokens': 0,
    },
  },
  'warnings': <String>[],
  'provider': 'local',
  'model': 'deterministic-template-v1',
  'generated_at': '2026-07-30T00:00:00Z',
};

const String _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _digestC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
