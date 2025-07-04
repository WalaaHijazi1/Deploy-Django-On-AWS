From python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install no-cache-dir -r requirements.txt

COPY . .

CMD ["python3","server.wsgi:application","django","--bind","0.0.0.0:8000"]
