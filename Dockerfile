FROM node:12.22.5

RUN rm -f /etc/localtime \
    && ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime \
    && apt-get update \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367 \
    && echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" | tee /etc/apt/sources.list.d/ansible.list \
    && apt-get update && apt-get install -y yarn ansible


ENV BUILD_PATH /build
ENV DEPLOY_PATH /deploy

RUN useradd -m builduser
RUN mkdir /src \
    && mkdir /build \
    && mkdir /deploy \
    && chmod -R 777 /src \
    && chmod -R 777 /build \
    && chmod -R 777 /deploy
USER builduser
ENV PATH="/home/builduser/.yarn/bin:$PATH"

WORKDIR /src/
COPY --chown=builduser:builduser . .
RUN yarn \
    && yarn build

ENTRYPOINT HOME=/home/builduser node /src/dist/main.js
