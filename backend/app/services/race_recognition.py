from __future__ import annotations

import asyncio
import base64
import json
from datetime import date
from typing import Literal, Protocol

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.config import Settings
from app.core.errors import ApiError

RaceTypeValue = Literal[
    "marathon",
    "trail_running",
    "hyrox",
    "road_running",
]


class RecognizedRaceFields(BaseModel):
    """经服务端验证后允许返回给客户端的赛事字段。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=120)
    type: RaceTypeValue | None = None
    race_date: str | None = None
    target_result: str | None = Field(default=None, max_length=80)
    course_info: str | None = Field(default=None, max_length=500)

    @field_validator("name", "target_result", "course_info")
    @classmethod
    def empty_string_to_none(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    @field_validator("race_date")
    @classmethod
    def validate_race_date(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        try:
            return date.fromisoformat(value.strip()).isoformat()
        except ValueError as error:
            raise ValueError("赛事日期必须使用 YYYY-MM-DD") from error


class MiniMaxModelOutput(BaseModel):
    """MiniMax 必须遵守的内部 JSON 输出结构。"""

    model_config = ConfigDict(extra="forbid")

    fields: RecognizedRaceFields
    warnings: list[str] = Field(default_factory=list, max_length=8)
    sensitive_content: bool = False

    @field_validator("warnings")
    @classmethod
    def normalize_warnings(cls, values: list[str]) -> list[str]:
        return [value.strip()[:120] for value in values if value.strip()]


class RaceRecognitionResult(BaseModel):
    """图片识别服务输出，不包含模型原始响应。"""

    provider: Literal["minimax"] = "minimax"
    model: str
    fields: RecognizedRaceFields
    normalized_text: str
    matched_field_count: int
    warnings: list[str]


class MiniMaxClient(Protocol):
    async def recognize(self, image_data_url: str) -> MiniMaxModelOutput:
        """发送图片并返回已经验证的模型结构。"""


class HttpMiniMaxClient:
    """MiniMax OpenAI 兼容图片聊天接口适配器。"""

    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._settings = settings
        self._transport = transport

    async def recognize(self, image_data_url: str) -> MiniMaxModelOutput:
        api_key = self._settings.minimax_api_key
        if api_key is None or not api_key.get_secret_value().strip():
            raise ApiError(503, "minimax_not_configured", "赛事图片识别尚未配置")

        payload = {
            "model": self._settings.minimax_model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": _recognition_prompt()},
                        {
                            "type": "image_url",
                            "image_url": {"url": image_data_url},
                        },
                    ],
                },
            ],
            "temperature": 0,
            "max_completion_tokens": 700,
            "thinking": {"type": "disabled"},
        }
        headers = {
            "Authorization": f"Bearer {api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        endpoint = f"{self._settings.minimax_base_url.rstrip('/')}/v1/chat/completions"

        try:
            async with asyncio.timeout(self._settings.minimax_timeout_seconds):
                async with httpx.AsyncClient(
                    timeout=httpx.Timeout(self._settings.minimax_timeout_seconds),
                    transport=self._transport,
                ) as client:
                    response = await self._post_with_retry(
                        client,
                        endpoint,
                        headers,
                        payload,
                    )
        except (TimeoutError, httpx.TimeoutException) as error:
            raise ApiError(
                504,
                "minimax_timeout",
                "赛事图片识别超时，请稍后重试",
            ) from error

        try:
            body = response.json()
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError
            return MiniMaxModelOutput.model_validate(json.loads(content))
        except (
            KeyError,
            IndexError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
        ) as error:
            raise ApiError(
                502,
                "minimax_invalid_output",
                "赛事图片识别结果无法解析，请换一张清晰图片重试",
            ) from error

    async def _post_with_retry(
        self,
        client: httpx.AsyncClient,
        endpoint: str,
        headers: dict[str, str],
        payload: dict[str, object],
    ) -> httpx.Response:
        for attempt in range(2):
            try:
                response = await client.post(endpoint, headers=headers, json=payload)
            except httpx.TimeoutException:
                raise
            except httpx.RequestError as error:
                if attempt == 0:
                    await asyncio.sleep(0)
                    continue
                raise ApiError(
                    502,
                    "minimax_connection_failed",
                    "赛事图片识别服务暂时无法连接",
                ) from error

            if response.status_code >= 500 and attempt == 0:
                continue
            if response.status_code == 429:
                raise ApiError(
                    429,
                    "minimax_rate_limited",
                    "图片识别服务繁忙，请稍后重试",
                )
            if response.status_code >= 400:
                raise ApiError(
                    502,
                    "minimax_upstream_failed",
                    "赛事图片识别服务返回异常",
                )
            return response

        raise ApiError(502, "minimax_upstream_failed", "赛事图片识别服务返回异常")


class RaceRecognitionService:
    """校验图片并把模型输出转换为稳定的赛事导入文本。"""

    def __init__(self, settings: Settings, client: MiniMaxClient) -> None:
        self._settings = settings
        self._client = client

    async def recognize(self, image: bytes) -> RaceRecognitionResult:
        if not image:
            raise ApiError(400, "image_empty", "请选择赛事图片")
        if len(image) > self._settings.race_image_max_bytes:
            raise ApiError(413, "image_too_large", "图片不能超过 10MB")

        mime_type = detect_image_mime_type(image)
        if mime_type is None:
            raise ApiError(
                415,
                "image_type_unsupported",
                "仅支持 JPEG、PNG、GIF 或 WebP 图片，HEIC 请先转换格式",
            )

        encoded = base64.b64encode(image).decode("ascii")
        model_output = await self._client.recognize(
            f"data:{mime_type};base64,{encoded}",
        )
        if model_output.sensitive_content:
            raise ApiError(
                422,
                "image_content_unsupported",
                "该图片不适合用于赛事信息识别",
            )

        fields = model_output.fields
        warnings = list(model_output.warnings)
        if fields.name is None:
            warnings.append("未能确认赛事名称，请手动补充")
        if fields.race_date is None:
            warnings.append("未能确认比赛日期，请手动补充")
        normalized_text = _normalized_text(fields)
        matched_count = sum(
            value is not None
            for value in (
                fields.name,
                fields.type,
                fields.race_date,
                fields.target_result,
                fields.course_info,
            )
        )
        return RaceRecognitionResult(
            model=self._settings.minimax_model,
            fields=fields,
            normalized_text=normalized_text,
            matched_field_count=matched_count,
            warnings=list(dict.fromkeys(warnings)),
        )


def detect_image_mime_type(image: bytes) -> str | None:
    if image.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if image.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if image.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if len(image) >= 12 and image[:4] == b"RIFF" and image[8:12] == b"WEBP":
        return "image/webp"
    return None


def _normalized_text(fields: RecognizedRaceFields) -> str:
    rows: list[str] = []
    if fields.name is not None:
        rows.append(f"赛事：{fields.name}")
    if fields.type is not None:
        rows.append(f"类型：{fields.type}")
    if fields.race_date is not None:
        rows.append(f"日期：{fields.race_date}")
    if fields.target_result is not None:
        rows.append(f"目标：{fields.target_result}")
    if fields.course_info is not None:
        rows.append(f"赛道：{fields.course_info}")
    return "\n".join(rows)


def _recognition_prompt() -> str:
    return """你是赛事海报结构化识别器。只提取图片中明确可见的信息，禁止猜测。
返回且仅返回一个 JSON 对象，结构如下：
{"fields":{"name":null,"type":null,"race_date":null,"target_result":null,"course_info":null},"warnings":[],"sensitive_content":false}
type 只能是 marathon、trail_running、hyrox、road_running 或 null。
race_date 只能是 YYYY-MM-DD 或 null。
名称、日期无法确认时必须为 null 并写入中文 warnings。
course_info 可合并图片中明确出现的距离、地点、爬升和赛道描述。
不要输出 Markdown，不要补全图片中不存在的信息。"""
