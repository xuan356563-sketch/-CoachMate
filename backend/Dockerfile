FROM python:3.13-slim@sha256:7ce4b6dfe35e55397b7cda544f8a13f191b7ae28dc5aad71fe664dbc9bc2623f

ARG APP_VERSION=development

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

WORKDIR /app

COPY requirements.lock ./
RUN pip install --no-cache-dir --require-hashes -r requirements.lock

COPY app ./app

COPY alembic ./alembic
COPY alembic.ini ./

RUN addgroup --system trainmate \
    && adduser --system --ingroup trainmate --no-create-home trainmate \
    && chown -R trainmate:trainmate /app

USER trainmate

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
