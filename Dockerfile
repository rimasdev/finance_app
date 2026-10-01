FROM python:3.12-slim

WORKDIR /srv

COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api /srv

ENV PYTHONUNBUFFERED=1
EXPOSE 3120

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "3120"]
