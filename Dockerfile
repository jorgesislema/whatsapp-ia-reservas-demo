# ============================================================================
# Dockerfile para Backend (FastAPI + WhatsApp IA Reservas)
# ============================================================================
#
# Construir: docker build -t wa-backend:latest .
# Pruebar localmente: docker run -p 8000:8000 wa-backend:latest
#
# ============================================================================

# Stage 1: Builder
FROM python:3.13-slim as builder

WORKDIR /app

# Instalar dependencias del sistema para compilar
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements
COPY requirements.txt .

# Crear virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Instalar dependencias Python
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

# ============================================================================
# Stage 2: Runtime
FROM python:3.13-slim

WORKDIR /app

# Instalar solo runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copiar virtualenv del builder
COPY --from=builder /opt/venv /opt/venv

# Copiar código de la aplicación
COPY wa_orchestrator ./wa_orchestrator
COPY panel ./panel
COPY config.py .

# Configurar PATH
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import httpx; httpx.get('http://localhost:8000/healthz', timeout=5)"

# Port
EXPOSE 8000

# Cloud Run entrypoint
# Cloud Run ejecuta: "python -m gunicorn --bind 0.0.0.0:8000 wa_orchestrator.main:app"
# Pero para uvicorn:
CMD ["python", "-m", "uvicorn", "wa_orchestrator.main:app", "--host", "0.0.0.0", "--port", "8000"]
