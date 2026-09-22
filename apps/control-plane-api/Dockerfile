FROM python:3.12.8-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app

WORKDIR /app

COPY apps/control-plane-api/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY apps/control-plane-api/app ./app
COPY apps/control-plane-api/alembic ./alembic
COPY apps/control-plane-api/alembic.ini ./alembic.ini
COPY apps/control-plane-api/tests ./tests
