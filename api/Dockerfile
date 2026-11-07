FROM ghcr.io/astral-sh/uv:0.11.15 AS uv

FROM python:3.15.1-slim

COPY --from=uv /uv /uvx /usr/local/bin/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONPATH=/app/src

WORKDIR /app

# Dependencias primero para aprovechar la caché de capas.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Código y proyecto instalado en el entorno virtual.
COPY src ./src
RUN uv sync --frozen --no-dev

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

CMD ["uvicorn", "bodega_api.main:app", "--host", "0.0.0.0", "--port", "8000"]
