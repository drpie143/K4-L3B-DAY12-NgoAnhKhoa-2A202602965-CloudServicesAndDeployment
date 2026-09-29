# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (Production-ready)
#
# Multi-stage build: stage builder cài dependency, stage runtime
# chỉ copy kết quả → image nhỏ (~200MB thay vì ~1GB).
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: Builder ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Copy requirements TRƯỚC để tận dụng Docker layer cache
# (sửa code không phải cài lại thư viện)
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ─────────────────────────────────────────────
FROM python:3.11-slim AS runtime

WORKDIR /app

# Copy dependency đã cài từ builder (không mang theo compiler)
COPY --from=builder /install /usr/local

# Tạo user thường — không chạy root
RUN useradd --create-home --uid 10001 appuser

# Copy source code SAU (layer cache cho deps vẫn giữ)
COPY app ./app
COPY utils ./utils

# Chuyển sang user thường
USER appuser

EXPOSE 8000

# Healthcheck gọi /health
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT:-8000}/health').read()" || exit 1

# Đọc PORT từ biến môi trường (cloud tự gán cổng)
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
