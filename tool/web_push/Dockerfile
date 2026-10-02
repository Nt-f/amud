FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py .
RUN mkdir /data && useradd --system push && chown push /data
USER push
EXPOSE 8080
CMD ["python", "server.py"]
