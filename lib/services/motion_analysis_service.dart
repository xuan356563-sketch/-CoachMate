import '../data/models/exercise_body_profile.dart';
import '../data/models/motion_check.dart';
import '../data/models/motion_pose.dart';
import 'motion_pose_analysis_service.dart';

class MotionAnalysisService {
  final MotionPoseAnalysisService _poseAnalysisService =
      MotionPoseAnalysisService();

  MotionAnalysisResult buildMockResult({
    required MotionCheckRule rule,
    required DateTime capturedAt,
    ExerciseBodyProfile? bodyProfile,
  }) {
    final TrainingDecisionImpact impact = _impactForRisk(rule.riskLevel);

    return MotionAnalysisResult(
      id: 'motion-analysis-${capturedAt.millisecondsSinceEpoch}',
      sourceRuleId: rule.id,
      type: rule.type,
      title: '${rule.type.label}动作分析',
      score: rule.score,
      riskLevel: rule.riskLevel,
      capturedAt: capturedAt,
      detectedErrors: rule.commonIssues.take(2).toList(),
      involvedAreas:
          bodyProfile != null && bodyProfile.involvedJoints.isNotEmpty
              ? bodyProfile.involvedJoints
              : _involvedAreas(rule.type),
      bodyEngineSummary: _bodyEngineSummary(
        rule.type,
        rule.commonIssues,
        bodyProfile,
      ),
      decisionImpact: _decisionImpact(rule.riskLevel, rule.type),
      suggestedImpact: impact,
      replacementActions: rule.regressions.take(2).toList(),
      evidenceSources: rule.evidenceSources,
    );
  }

  MotionAnalysisResult buildPoseResult({
    required MotionCheckRule rule,
    required MotionPoseFrame frame,
    required DateTime capturedAt,
    ExerciseBodyProfile? bodyProfile,
  }) {
    final MotionPoseAnalysis analysis = _poseAnalysisService.analyze(
      type: rule.type,
      frame: frame,
    );
    final TrainingDecisionImpact impact = _impactForRisk(analysis.riskLevel);
    final List<String> errors = analysis.detectedErrors.isEmpty
        ? rule.commonIssues.take(2).toList()
        : analysis.detectedErrors.take(3).toList();

    return MotionAnalysisResult(
      id: 'motion-pose-analysis-${capturedAt.millisecondsSinceEpoch}',
      sourceRuleId: rule.id,
      type: rule.type,
      title: '${rule.type.label}关键点几何分析',
      score: analysis.score,
      riskLevel: analysis.riskLevel,
      capturedAt: capturedAt,
      detectedErrors: errors,
      involvedAreas:
          bodyProfile != null && bodyProfile.involvedJoints.isNotEmpty
              ? bodyProfile.involvedJoints
              : _involvedAreas(rule.type),
      bodyEngineSummary: _bodyEngineSummary(
        rule.type,
        errors,
        bodyProfile,
      ),
      decisionImpact: _decisionImpact(analysis.riskLevel, rule.type),
      suggestedImpact: impact,
      replacementActions: rule.regressions.take(2).toList(),
      evidenceSources: rule.evidenceSources,
      analysisSource: '本地关键点几何分析（不等同相机识别）',
      analysisConfidence: analysis.confidence,
      angleMetrics: [
        for (final MotionPoseMeasurement measurement in analysis.measurements)
          '${measurement.label} ${measurement.valueLabel}',
      ],
      poseFrame: frame,
    );
  }

  TrainingDecisionImpact _impactForRisk(MotionRiskLevel riskLevel) {
    switch (riskLevel) {
      case MotionRiskLevel.low:
        return TrainingDecisionImpact.keep;
      case MotionRiskLevel.medium:
        return TrainingDecisionImpact.deload;
      case MotionRiskLevel.high:
        return TrainingDecisionImpact.technique;
    }
  }

  List<String> _involvedAreas(MotionCheckType type) {
    switch (type) {
      case MotionCheckType.squat:
      case MotionCheckType.lunge:
        return const ['髋', '膝', '踝', '臀中肌'];
      case MotionCheckType.hipHinge:
        return const ['髋', '腰背', '腘绳肌'];
      case MotionCheckType.pushUp:
        return const ['肩', '肘', '核心'];
      case MotionCheckType.plank:
        return const ['核心', '肩胛', '腰椎'];
      case MotionCheckType.calfRaise:
        return const ['小腿', '跟腱', '足底'];
      case MotionCheckType.highKnee:
        return const ['髋屈肌', '核心', '踝'];
      case MotionCheckType.sideRun:
        return const ['髋', '膝', '小腿', '足底'];
    }
  }

  String _bodyEngineSummary(
    MotionCheckType type,
    List<String> commonIssues,
    ExerciseBodyProfile? bodyProfile,
  ) {
    final String issue = commonIssues.isEmpty ? '动作稳定性不足' : commonIssues.first;
    if (bodyProfile != null && bodyProfile.isStructured) {
      return '$issue；${bodyProfile.bodyEngineSummary}；常见代偿：${bodyProfile.commonCompensations.join('、')}。';
    }
    switch (type) {
      case MotionCheckType.squat:
      case MotionCheckType.lunge:
        return '$issue 可能来自髋控制、足踝稳定和膝轨迹协同不足。';
      case MotionCheckType.hipHinge:
        return '$issue 可能让腰椎代偿髋部折叠，需要先降到可控动作。';
      case MotionCheckType.pushUp:
      case MotionCheckType.plank:
        return '$issue 提示肩胛控制和核心抗伸展能力需要优先处理。';
      case MotionCheckType.calfRaise:
        return '$issue 会增加跟腱和足底负担，跑跳课前需要保守处理。';
      case MotionCheckType.highKnee:
        return '$issue 会影响跑姿练习节奏，应先降低速度做技术修正。';
      case MotionCheckType.sideRun:
        return '$issue 可能提高小腿、跟腱和膝部压力，今天不宜叠加强刺激。';
    }
  }

  String _decisionImpact(MotionRiskLevel riskLevel, MotionCheckType type) {
    switch (riskLevel) {
      case MotionRiskLevel.low:
        return '${type.label}动作质量可接受，今日训练保持原计划，继续记录反馈。';
      case MotionRiskLevel.medium:
        return '${type.label}存在中等风险，今日主训练建议降一档并加入替代动作。';
      case MotionRiskLevel.high:
        return '${type.label}存在高风险，今日训练建议转为技术练习或低冲击替代。';
    }
  }
}
