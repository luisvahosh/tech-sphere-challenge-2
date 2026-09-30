# Una sola imagen para los dos servicios (API FastAPI y consola Streamlit);
# docker-compose.yml decide cual arranca cada contenedor.
# Python 3.11: chroma-hnswlib==0.7.6 solo trae wheel precompilado hasta 3.11.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONUTF8=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Estado persistente fuera del codigo, montado como volumen
    CHROMA_DIR=/app/data/chroma_db \
    LLAMADAS_DB_PATH=/app/data/llamadas.db \
    # Sin telemetria de ChromaDB ni de Streamlit
    ANONYMIZED_TELEMETRY=False \
    STREAMLIT_BROWSER_GATHER_USAGE_STATS=false \
    STREAMLIT_SERVER_HEADLESS=true

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY backend/ backend/
COPY call-interface/ call-interface/
COPY console/ console/
COPY .streamlit/ .streamlit/

RUN useradd --create-home --uid 1000 app \
    && mkdir -p /app/data \
    && chown -R app:app /app/data
USER app

EXPOSE 8000 8501

# Por defecto arranca la API; la consola sobreescribe el comando en compose.
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
