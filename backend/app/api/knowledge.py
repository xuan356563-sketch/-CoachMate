from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.knowledge_catalog import KnowledgeCatalog, KnowledgeCatalogService

router = APIRouter(prefix="/v1/knowledge", tags=["训练知识"])


@router.get(
    "/catalog",
    response_model=KnowledgeCatalog,
    summary="读取已审核训练知识目录",
)
def get_knowledge_catalog(
    _claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> KnowledgeCatalog:
    """只返回自编摘要、结构模板和来源定位，不返回书籍原文。"""
    if not settings.knowledge_catalog_enabled:
        raise ApiError(
            503,
            "knowledge_catalog_unavailable",
            "训练知识目录暂时关闭，请使用本地训练内容。",
        )
    service = KnowledgeCatalogService(session)
    service.ensure_seeded()
    return service.catalog()
