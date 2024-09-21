FROM cgr.dev/chainguard/python:latest-dev AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt \
    && chmod 777 /home/nonroot/.local/lib/python3.12/site-packages/flask

FROM cgr.dev/chainguard/python:latest
WORKDIR /opt/app
COPY app/app.py .
COPY --from=builder /home/nonroot/.local/lib/python3.12/site-packages /home/nonroot/.local/lib/python3.12/site-packages
COPY --from=builder /home/nonroot/.local/bin  /home/nonroot/.local/bin
ENV PATH=$PATH:/home/nonroot/.local/bin
ENV PYTHONPATH=/home/nonroot/.local/lib/python3.12/site-packages
EXPOSE 5000
ENTRYPOINT ["flask", "run", "--host=0.0.0.0"]
