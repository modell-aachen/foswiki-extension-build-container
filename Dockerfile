FROM ubuntu:22.04

USER root

ARG NODE_VERSION="v16.19.0"

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
    git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    sshpass \
    yarn \
    && rm -rf /var/lib/apt/lists/*
    
RUN pip3 install pyvmomi
RUN pip3 install --upgrade git+https://github.com/vmware/vsphere-automation-sdk-python.git@v8.0.0.0
RUN pip3 install ansible

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

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.2/install.sh | bash

RUN . "$NVM_DIR/nvm.sh" \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

ENV NODE_PATH="$NVM_DIR/v${NODE_VERSION}/lib/node_modules"
ENV PATH="$NVM_DIR/v${NODE_VERSION}/bin:$PATH"

WORKDIR /src/
COPY --chown=builduser:builduser . .
RUN yarn \
    && yarn build

ENTRYPOINT HOME=/home/builduser node /src/dist/main.js
