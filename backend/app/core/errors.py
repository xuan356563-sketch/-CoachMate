from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ApiError(Exception):
    """面向客户端的受控错误，避免泄露内部实现细节。"""

    def __init__(self, status_code: int, code: str, detail: str) -> None:
        self.status_code = status_code
        self.code = code
        self.detail = detail


async def api_error_handler(_request: Request, error: ApiError) -> JSONResponse:
    """统一输出中文错误信息和稳定错误码。"""
    return JSONResponse(
        status_code=error.status_code,
        content={"code": error.code, "detail": error.detail},
    )


async def request_validation_error_handler(
    request: Request,
    error: RequestValidationError,
) -> JSONResponse:
    """训练处方拒绝回显非法健康字段，其他接口保持 FastAPI 兼容格式。"""
    if request.url.path.startswith("/v1/sync/"):
        return JSONResponse(
            status_code=422,
            content={
                "code": "sync_payload_invalid",
                "detail": "同步请求包含未声明或不允许的字段。",
            },
        )
    if request.url.path.startswith("/v1/account/"):
        return JSONResponse(
            status_code=422,
            content={
                "code": "account_request_invalid",
                "detail": "账号请求包含无效或未声明的字段。",
            },
        )
    if request.url.path.startswith("/v1/coach/"):
        return JSONResponse(
            status_code=422,
            content={
                "code": "coach_request_invalid",
                "detail": "Coach 请求包含无效、未声明或不允许的字段。",
            },
        )
    if request.url.path in {
        "/v1/ai/training-prescriptions",
        "/v2/ai/training-prescriptions",
        "/v1/ai/chat",
    }:
        code = (
            "training_plan_request_invalid"
            if request.url.path.endswith("training-prescriptions")
            else "ai_chat_request_invalid"
        )
        return JSONResponse(
            status_code=422,
            content={
                "code": code,
                "detail": "请求包含无效或不允许的字段。",
            },
        )
    return JSONResponse(
        status_code=422,
        content={"detail": jsonable_encoder(error.errors())},
    )
