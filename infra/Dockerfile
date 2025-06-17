FROM python:3.9-slim

WORKDIR /app
COPY src/ .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["python", "main.py"]
