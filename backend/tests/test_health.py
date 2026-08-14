from fastapi.testclient import TestClient

from app.api.health import ReadinessChecks, get_readiness_probe
from app.main import create_app


class StaticReadinessProbe:
    """返回测试指定状态的就绪探针。"""

    def __init__(self, checks: ReadinessChecks) -> None:
        self._checks = checks

    def check(self) -> ReadinessChecks:
        return self._checks


def test_health_check_returns_non_sensitive_service_status() -> None:
    client = TestClient(create_app())

    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "TrainFlow API",
        "environment": "development",
    }


def test_openapi_exposes_health_contract() -> None:
    client = TestClient(create_app())

    response = client.get("/openapi.json")

    assert response.status_code == 200
    assert "/healthz" in response.json()["paths"]
    assert "/readyz" in response.json()["paths"]


def test_readiness_check_returns_ready_when_all_dependencies_are_healthy() -> None:
    app = create_app()
    app.dependency_overrides[get_readiness_probe] = lambda: StaticReadinessProbe(
        ReadinessChecks(database="ok", redis="ok", migration="ok")
    )
    client = TestClient(app)

    response = client.get("/readyz")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "service": "TrainFlow API",
        "environment": "development",
        "version": "development",
        "checks": {"database": "ok", "redis": "ok", "migration": "ok"},
    }


def test_readiness_check_returns_503_without_sensitive_error_details() -> None:
    app = create_app()
    app.dependency_overrides[get_readiness_probe] = lambda: StaticReadinessProbe(
        ReadinessChecks(database="ok", redis="error", migration="error")
    )
    client = TestClient(app)

    response = client.get("/readyz")

    assert response.status_code == 503
    assert response.json() == {
        "status": "not_ready",
        "service": "TrainFlow API",
        "environment": "development",
        "version": "development",
        "checks": {
            "database": "ok",
            "redis": "error",
            "migration": "error",
        },
    }
