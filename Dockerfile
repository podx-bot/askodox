FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Temporary migration bridge: pin the previously working ASKODOX V2 backend
# so Railway can deploy from the single askodox repository while the backend
# source is being fully vendored into /backend.
ARG BACKEND_COMMIT=915327953098ab64ecedcfd9553580bbf48f8af1
RUN curl -fsSL "https://github.com/podx-bot/podx-ai-connect-v2/archive/${BACKEND_COMMIT}.zip" -o /tmp/backend.zip \
    && unzip -q /tmp/backend.zip -d /tmp/backend-src \
    && cp -a /tmp/backend-src/podx-ai-connect-v2-${BACKEND_COMMIT}/. /app/ \
    && rm -rf /tmp/backend.zip /tmp/backend-src

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn server:app --host 0.0.0.0 --port ${PORT:-8000}"]
