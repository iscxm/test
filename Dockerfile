FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    iptables \
    python3 \
    screen \
    tmux \
    sudo \
    && rm -rf /var/lib/apt/lists/*

COPY toxic.sh /usr/local/bin/toxic.sh
RUN chmod +x /usr/local/bin/toxic.sh

WORKDIR /usr/local/bin

CMD ["bash", "toxic.sh", "dev", "toxic"]
