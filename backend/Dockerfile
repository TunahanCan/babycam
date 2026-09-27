FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt constraints.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt \
    && useradd --uid 10001 --create-home billing \
    && mkdir /data && chown billing:billing /data
COPY miucam_billing/ ./miucam_billing/
USER billing
EXPOSE 8080
VOLUME /data
CMD ["uvicorn", "miucam_billing.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--limit-concurrency", "64", "--timeout-keep-alive", "5", "--no-access-log"]
