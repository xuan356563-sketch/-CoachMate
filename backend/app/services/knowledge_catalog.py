from __future__ import annotations

from collections.abc import Sequence

from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.knowledge import KnowledgePrincipleRecord, TrainingTemplateRecord

KNOWLEDGE_CATALOG_VERSION = "2026.08.02-v2"


class KnowledgePrinciple(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: str
    title: str
    summary: str
    tags: list[str]
    source_label: str
    source_section: str
    content_version: str


class TrainingTemplate(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: str
    title: str
    population_template_id: str
    goals: list[str]
    primary_sports: list[str]
    supported_days: list[int]
    required_equipment: list[str]
    session_pattern: list[str]
    source_label: str
    content_version: str


class PopulationTemplate(BaseModel):
    id: str
    title: str
    automatic_plan_allowed: bool
    progression_mode: str
    schedule_modifier: str | None = None
    screening_extension_codes: list[str]
    derived_constraint_codes: list[str]
    session_structure_codes: list[str]
    progression_rule_codes: list[str]


class KnowledgeCatalog(BaseModel):
    version: str
    principles: list[KnowledgePrinciple]
    training_templates: list[TrainingTemplate]
    population_templates: list[PopulationTemplate]


class KnowledgeRetrievalResult(BaseModel):
    version: str
    principles: list[KnowledgePrinciple]
    training_templates: list[TrainingTemplate]
    is_unambiguous: bool


_POPULATION_TEMPLATES = (
    PopulationTemplate(
        id="sedentary_beginner",
        title="久坐办公初学者",
        automatic_plan_allowed=True,
        progression_mode="conservative",
        screening_extension_codes=["adult_low_risk"],
        derived_constraint_codes=["avoid_compensatory_volume"],
        session_structure_codes=["strength_easy_mobility"],
        progression_rule_codes=["one_variable_per_week"],
    ),
    PopulationTemplate(
        id="low_impact_fat_loss",
        title="低冲击减脂",
        automatic_plan_allowed=True,
        progression_mode="conservative",
        screening_extension_codes=["impact_tolerance_check"],
        derived_constraint_codes=["avoid_punitive_jumping"],
        session_structure_codes=["strength_walk_cardio"],
        progression_rule_codes=["conservative_single_variable"],
    ),
    PopulationTemplate(
        id="strength_progression",
        title="力量与增肌进阶",
        automatic_plan_allowed=True,
        progression_mode="balanced",
        screening_extension_codes=["movement_quality_check"],
        derived_constraint_codes=["preserve_recovery_spacing"],
        session_structure_codes=["push_pull_squat_hinge_core"],
        progression_rule_codes=["balanced_single_variable"],
    ),
    PopulationTemplate(
        id="running_entry_or_race",
        title="跑步入门或备赛",
        automatic_plan_allowed=True,
        progression_mode="balanced",
        screening_extension_codes=["race_and_impact_check"],
        derived_constraint_codes=["separate_long_and_quality"],
        session_structure_codes=["easy_quality_strength_long"],
        progression_rule_codes=["distance_or_intensity_not_both"],
    ),
    PopulationTemplate(
        id="hyrox_hybrid",
        title="HYROX 混合体能",
        automatic_plan_allowed=True,
        progression_mode="balanced",
        screening_extension_codes=["hybrid_work_capacity_check"],
        derived_constraint_codes=["preserve_run_strength_balance"],
        session_structure_codes=["run_strength_station_mobility"],
        progression_rule_codes=["balanced_single_variable"],
    ),
    PopulationTemplate(
        id="older_adult_foundation",
        title="老年基础低冲击",
        automatic_plan_allowed=True,
        progression_mode="conservative",
        schedule_modifier="recovery_spacing",
        screening_extension_codes=["older_adult_preexercise_clearance"],
        derived_constraint_codes=["low_impact_and_balance_first"],
        session_structure_codes=["strength_balance_aerobic_mobility"],
        progression_rule_codes=["conservative_single_variable"],
    ),
    PopulationTemplate(
        id="shift_worker_flexible",
        title="轮班人群弹性日程",
        automatic_plan_allowed=True,
        progression_mode="conservative",
        schedule_modifier="flexible_anchor_days",
        screening_extension_codes=["sleep_and_schedule_check"],
        derived_constraint_codes=["avoid_makeup_volume"],
        session_structure_codes=["anchor_flexible_recovery"],
        progression_rule_codes=["consistency_before_load"],
    ),
    PopulationTemplate(
        id="return_to_training_guarded",
        title="伤病后重返训练",
        automatic_plan_allowed=False,
        progression_mode="conservative",
        schedule_modifier="manual_clearance_only",
        screening_extension_codes=["clinical_clearance_required"],
        derived_constraint_codes=["no_automatic_plan"],
        session_structure_codes=["screening_and_referral_only"],
        progression_rule_codes=["manual_clearance_before_progression"],
    ),
)

_PRINCIPLES = (
    (
        "periodization",
        "周期化",
        "先建立基础，再进入专项；只有明确赛事信息时才进入减量阶段。",
        ["general_fitness", "race_preparation", "marathon", "hyrox"],
        "TrainMate 内部训练原则",
        "周期结构",
    ),
    (
        "progressive_overload",
        "渐进负荷",
        "每周只推进一个变量，具体增长上限由本地编译器执行。",
        ["strength", "fat_loss", "endurance"],
        "TrainMate 内部训练原则",
        "负荷进阶",
    ),
    (
        "recovery_spacing",
        "恢复间隔",
        "避免连续堆叠高负荷课程，每周至少保留一节低强度课程。",
        ["general_fitness", "strength", "endurance", "hyrox"],
        "TrainMate 内部训练原则",
        "恢复安排",
    ),
    (
        "specificity",
        "专项性",
        "主要课程必须服务当前主运动，次运动只作为辅助且不增加训练天数。",
        ["strength", "endurance", "race_preparation"],
        "TrainMate 内部训练原则",
        "专项匹配",
    ),
    (
        "low_intensity_base",
        "低强度基础",
        "基础阶段以可持续的低至中等强度建立有氧和工作能力。",
        ["fat_loss", "endurance", "marathon", "trail_running"],
        "TrainMate 内部训练原则",
        "有氧基础",
    ),
    (
        "deload",
        "主动减量",
        "连续推进后安排减量周，减量幅度和触发条件由本地规则裁决。",
        ["strength", "endurance", "hyrox"],
        "TrainMate 内部训练原则",
        "减量安排",
    ),
    (
        "beginner_safety",
        "初学者保守进阶",
        "初学者优先动作质量与稳定习惯，不安排挑战强度和密集间歇。",
        ["beginner", "sedentary_beginner"],
        "TrainMate 内部训练原则",
        "初学者",
    ),
    (
        "strength_foundation",
        "全身力量基础",
        "力量入门先覆盖推、拉、蹲、髋和核心模式，再增加专项容量。",
        ["strength", "strength_progression"],
        "TrainMate 内部训练原则",
        "力量基础",
    ),
    (
        "run_load_balance",
        "跑步负荷平衡",
        "一周内分离长距离与质量课，其余跑步以轻松强度支持恢复。",
        ["endurance", "marathon", "trail_running"],
        "TrainMate 内部训练原则",
        "跑步结构",
    ),
    (
        "hyrox_transition",
        "混合体能转换",
        "HYROX 训练同时保留跑步、基础力量和少量专项转换刺激。",
        ["hyrox", "hyrox_hybrid"],
        "TrainMate 内部训练原则",
        "HYROX",
    ),
    (
        "low_impact",
        "低冲击优先",
        "低冲击减脂优先力量、步行和器械有氧，不使用惩罚性跳跃堆量。",
        ["fat_loss", "low_impact_fat_loss"],
        "TrainMate 内部训练原则",
        "低冲击",
    ),
    (
        "schedule_consistency",
        "日程一致性",
        "优先选择能长期完成的训练频次和时长，不用单周激进安排补偿漏练。",
        ["general_fitness", "sedentary_beginner", "shift_work"],
        "TrainMate 内部训练原则",
        "日程约束",
    ),
    (
        "older_adult_foundation",
        "老年基础训练",
        "筛查通过后优先低冲击有氧、基础力量、平衡和活动度，并保留更充分恢复间隔。",
        ["older_adult_foundation", "general_fitness"],
        "TrainMate 内部训练原则",
        "老年基础",
    ),
    (
        "shift_work_flexibility",
        "轮班弹性安排",
        "以锚点课程和可移动恢复日适配轮班，不通过补课堆叠训练负荷。",
        ["shift_worker_flexible", "shift_work", "general_fitness"],
        "TrainMate 内部训练原则",
        "轮班日程",
    ),
    (
        "return_to_training_guard",
        "重返训练安全门",
        "伤病后重返训练只提供筛查和转介要求，未获得人工许可前不自动生成计划。",
        ["return_to_training_guarded", "injury_history"],
        "TrainMate 内部训练原则",
        "重返训练",
    ),
)

_TRAINING_TEMPLATES = (
    (
        "general_balanced_3d",
        "通用均衡三日",
        "sedentary_beginner",
        ["general_fitness"],
        ["general_fitness"],
        [3],
        ["bodyweight"],
        ["strength", "easy_run", "mobility"],
    ),
    (
        "sedentary_beginner_3d",
        "久坐初学三日",
        "sedentary_beginner",
        ["general_fitness"],
        ["general_fitness"],
        [2, 3],
        ["bodyweight"],
        ["strength", "easy_run", "mobility"],
    ),
    (
        "low_impact_fat_loss_3d",
        "低冲击减脂三日",
        "low_impact_fat_loss",
        ["fat_loss"],
        ["general_fitness", "fat_loss"],
        [3],
        ["bodyweight"],
        ["strength", "easy_run", "cross_training"],
    ),
    (
        "strength_progression_3d",
        "力量进阶三日",
        "strength_progression",
        ["strength"],
        ["strength"],
        [3],
        ["bodyweight"],
        ["strength", "strength", "mobility"],
    ),
    (
        "run_beginner_3d",
        "跑步入门三日",
        "running_entry_or_race",
        ["endurance"],
        ["marathon", "trail_running"],
        [3],
        ["bodyweight"],
        ["easy_run", "strength", "long_run"],
    ),
    (
        "run_race_4d",
        "跑步备赛四日",
        "running_entry_or_race",
        ["race_preparation"],
        ["marathon", "trail_running"],
        [4],
        ["bodyweight"],
        ["easy_run", "tempo_run", "strength", "long_run"],
    ),
    (
        "hyrox_hybrid_4d",
        "HYROX 混合四日",
        "hyrox_hybrid",
        ["race_preparation", "endurance"],
        ["hyrox"],
        [4],
        ["bodyweight"],
        ["easy_run", "strength", "hyrox", "mobility"],
    ),
    (
        "older_adult_foundation_3d",
        "老年基础三日",
        "older_adult_foundation",
        ["general_fitness"],
        ["general_fitness"],
        [2, 3],
        ["bodyweight"],
        ["strength", "easy_run", "mobility"],
    ),
    (
        "shift_worker_flexible_3d",
        "轮班弹性三日",
        "shift_worker_flexible",
        ["general_fitness", "fat_loss"],
        ["general_fitness", "fat_loss"],
        [2, 3, 4],
        ["bodyweight"],
        ["strength", "easy_run", "mobility"],
    ),
)


class KnowledgeCatalogService:
    """维护审核内容，并以确定性排序控制检索数量。"""

    def __init__(self, session: Session) -> None:
        self._session = session

    def ensure_seeded(self) -> None:
        principle_records = {
            item.id: item
            for item in self._session.scalars(select(KnowledgePrincipleRecord))
        }
        template_records = {
            item.id: item
            for item in self._session.scalars(select(TrainingTemplateRecord))
        }
        for item in _PRINCIPLES:
            record = principle_records.get(item[0])
            if record is None:
                record = KnowledgePrincipleRecord(
                    id=item[0],
                )
                self._session.add(record)
            record.status = "verified"
            record.title = item[1]
            record.summary = item[2]
            record.tags = item[3]
            record.source_label = item[4]
            record.source_section = item[5]
            record.content_version = KNOWLEDGE_CATALOG_VERSION
        for item in _TRAINING_TEMPLATES:
            record = template_records.get(item[0])
            if record is None:
                record = TrainingTemplateRecord(
                    id=item[0],
                )
                self._session.add(record)
            record.status = "verified"
            record.title = item[1]
            record.population_template_id = item[2]
            record.goals = item[3]
            record.primary_sports = item[4]
            record.supported_days = item[5]
            record.required_equipment = item[6]
            record.session_pattern = item[7]
            record.source_label = "TrainMate 自编结构模板"
            record.content_version = KNOWLEDGE_CATALOG_VERSION
        self._session.commit()

    def catalog(self) -> KnowledgeCatalog:
        principles = self._verified_principles()
        templates = self._verified_templates()
        return KnowledgeCatalog(
            version=KNOWLEDGE_CATALOG_VERSION,
            principles=[
                KnowledgePrinciple.model_validate(item)
                for item in principles
            ],
            training_templates=[
                TrainingTemplate.model_validate(item)
                for item in templates
            ],
            population_templates=list(_POPULATION_TEMPLATES),
        )

    def retrieve(
        self,
        *,
        goal: str,
        primary_sport: str,
        population_template_id: str,
        equipment_access: Sequence[str],
        weekly_training_days: int | None = None,
    ) -> KnowledgeRetrievalResult:
        tags = {goal, primary_sport, population_template_id}
        principles = sorted(
            self._verified_principles(),
            key=lambda item: (
                -len(tags.intersection(item.tags)),
                item.id,
            ),
        )[:4]
        available = set(equipment_access)
        candidates = [
            item
            for item in self._verified_templates()
            if population_template_id == item.population_template_id
            and goal in item.goals
            and primary_sport in item.primary_sports
            and set(item.required_equipment).issubset(available)
            and (
                weekly_training_days is None
                or weekly_training_days in item.supported_days
            )
        ]
        templates = sorted(candidates, key=lambda item: item.id)[:1]
        return KnowledgeRetrievalResult(
            version=KNOWLEDGE_CATALOG_VERSION,
            principles=[
                KnowledgePrinciple.model_validate(item)
                for item in principles
            ],
            training_templates=[
                TrainingTemplate.model_validate(item)
                for item in templates
            ],
            is_unambiguous=len(candidates) == 1,
        )

    def _verified_principles(self) -> list[KnowledgePrincipleRecord]:
        return list(
            self._session.scalars(
                select(KnowledgePrincipleRecord)
                .where(KnowledgePrincipleRecord.status == "verified")
                .order_by(KnowledgePrincipleRecord.id),
            ),
        )

    def _verified_templates(self) -> list[TrainingTemplateRecord]:
        return list(
            self._session.scalars(
                select(TrainingTemplateRecord)
                .where(TrainingTemplateRecord.status == "verified")
                .order_by(TrainingTemplateRecord.id),
            ),
        )
