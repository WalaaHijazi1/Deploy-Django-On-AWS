FROM python:3.11-slim

WORKDIR /app

# Install system dependencies needed to compile mysqlclient
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["gunicorn", "wsgi:application", "--bind", "0.0.0.0:8000"]