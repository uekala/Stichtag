FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache python3

COPY app /app

CMD ["python3", "-u", "/app/server.py"]
