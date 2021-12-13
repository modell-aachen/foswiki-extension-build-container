FROM ubuntu:20.04

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_PATH /build
ENV DEPLOY_PATH /deploy


RUN rm -f /etc/localtime \
    && ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    gpg \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_12.x | bash -

RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ansible \
    python-is-python3 \
    sshpass \
    nodejs \
    yarn \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m builduser
RUN mkdir /src \
    && mkdir /build \
    && mkdir /deploy \
    && chmod -R 777 /src \
    && chmod -R 777 /build \
    && chmod -R 777 /deploy

USER builduser
ENV NVM_DIR="/home/builduser/.nvm"
ENV PATH="/home/builduser/.yarn/bin:$PATH"

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash -

# Install nvm for builduser user
RUN . "$NVM_DIR/nvm.sh" \
    && nvm install "lts/erbium" \
    && nvm install "lts/gallium" \
    && nvm use "lts/erbium"

WORKDIR /src/
COPY --chown=builduser:builduser . .
RUN yarn \
    && yarn build

ENTRYPOINT HOME=/home/builduser node /src/dist/main.js
