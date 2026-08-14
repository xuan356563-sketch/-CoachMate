import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/adaptation_signals.dart';
import 'package:trainflow_ai/data/models/plan_revision_proposal.dart';
import 'package:trainflow_ai/features/ai_center/data/plan_revision_api_models.dart';

void main() {
  test('周期重排请求只发送结构化训练上下文与安全约束代码', () {
    final Map<String, dynamic> json = PlanRevisionRequest(
      clientContextDigest: _hashA,
      remainingDates: <DateTime>[DateTime(2026, 8), DateTime(2026, 8, 2)],
      completedSessions: 3,
      missedSessions: 2,
      scheduleChangeDates: <DateTime>[DateTime(2026, 8, 2)],
      availableMinutes: 40,
      equipmentAccess: const <String>['bodyweight'],
      equipmentChanged: true,
      safetyConstraintCodes: const <String>['no_increase'],
      adaptationSignals: const AdaptationSignals(
        completionRateBand: 'medium',
        loadTrendCode: 'falling',
        recoveryRiskCode: 'advise',
        selectedDirectionCode: 'recovery_first',
      ),
      currentPrescription: _currentPrescription(),
    ).toJson();

    expect(json['remaining_dates'], <String>['2026-08-01', '2026-08-02']);
    final String encoded = jsonEncode(json);
    expect(encoded, isNot(contains('health_reason')));
    expect(encoded, isNot(contains('pain')));
    expect(encoded, isNot(contains('injury')));
    expect(encoded, contains('"completion_rate_band":"medium"'));
    expect(encoded, isNot(contains('recovery_text')));
  });

  test('周期重排差异与正文一致时可解析，且保持 pending', () {
    final AiArtifact artifact = AiArtifact.fromJson(<String, dynamic>{
      'id': 'revision-1',
      'capability': 'trainer',
      'artifact_type': 'plan_revision_v1',
      'schema_version': 1,
      'decision_status': 'pending',
      'context_digest': _hashB,
      'payload': <String, dynamic>{
        'proposal_status': 'pending',
        'client_context_digest': _hashA,
        'remaining_dates': <String>['2026-08-01', '2026-08-02'],
        'revised_prescription': <String, dynamic>{
          'cycle_focus': 'base',
          'progression_mode': 'conservative',
          'weekly_sessions': <Map<String, dynamic>>[
            <String, dynamic>{
              'training_type': 'strength',
              'duration_minutes': 36,
              'intensity_band': 'moderate',
              'focus_codes': <String>['full_body_strength'],
            },
          ],
        },
        'differences': <Map<String, dynamic>>[
          <String, dynamic>{
            'session_index': 0,
            'before_training_type': 'strength',
            'after_training_type': 'strength',
            'before_duration_minutes': 45,
            'after_duration_minutes': 36,
            'reason_code': 'local_safe_fallback',
          },
        ],
        'generation_meta': <String, dynamic>{
          'prompt_contract_version': 'plan-revision-v1',
          'generation_mode': 'local_safe_fallback',
          'app_cache_hit': false,
          'model': 'deterministic-plan-revision-v1',
          'input_tokens': 0,
          'output_tokens': 0,
        },
      },
      'warnings': <String>[],
      'provider': 'local',
      'model': 'deterministic-plan-revision-v1',
      'generated_at': '2026-07-30T00:00:00Z',
    });

    final PlanRevisionProposal proposal = PlanRevisionProposal.fromArtifact(
      artifact: artifact,
      currentPrescription: _currentPrescription(),
      expectedClientContextDigest: _hashA,
    );

    expect(proposal.artifact.isPending, isTrue);
    expect(
        proposal.revisedPrescription.weeklySessions.single.durationMinutes, 36);
    expect(proposal.differences.single.beforeDurationMinutes, 45);
  });
}

AiTrainingPrescription _currentPrescription() =>
    AiTrainingPrescription.fromJson(<String, dynamic>{
      'cycle_focus': 'base',
      'progression_mode': 'conservative',
      'weekly_sessions': <Map<String, dynamic>>[
        <String, dynamic>{
          'training_type': 'strength',
          'duration_minutes': 45,
          'intensity_band': 'moderate',
          'focus_codes': <String>['full_body_strength'],
        },
      ],
      'applied_skill': <String, dynamic>{
        'id': 'training-plan-builder',
        'version': '1.0.0',
        'display_name': '训练计划生成器',
        'source_sha256': _hashB,
        'runtime_sha256': _hashC,
        'fragment_sha256': null,
        'coverage': 'general_fitness',
      },
      'selection_reason': '主运动使用通用训练计划 Skill。',
      'selection_reason_code': 'generic_periodization_fallback',
      'generation_meta': <String, dynamic>{
        'contract_version': 2,
        'client_context_digest': _hashA,
        'prompt_contract_version': 'training-prescription-v2',
        'knowledge_snapshot_version': '2026.08.02-v2',
        'generation_mode': 'cloud_adaptation',
        'cache_hit': false,
        'app_cache_hit': false,
        'model': 'deepseek-v4-flash',
      },
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
    });

const String _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _hashC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
