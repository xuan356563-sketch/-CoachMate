FROM python:3.13-slim

ARG APP_VERSION=development

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app
RUN pip install --no-cache-dir .

COPY alembic ./alembic
COPY alembic.ini ./

RUN addgroup --system trainmate \
    && adduser --system --ingroup trainmate --no-create-home trainmate \
    && chown -R trainmate:trainmate /app

USER trainmate

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
