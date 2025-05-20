FROM python:3.13

RUN apt-get update && apt-get install -y curl && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl

WORKDIR /app

COPY requirements.txt /app/requirements.txt
COPY imbalance /app/imbalance
RUN pip install -r /app/requirements.txt
RUN pip install requests kubernetes

CMD ["python", "/app/imbalance/cli.py"]