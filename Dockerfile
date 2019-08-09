FROM node:8.16.0-jessie

RUN apt-get update
RUN apt-get install -y apt-transport-https curl libcss-minifier-perl libjavascript-minifier-perl libjson-perl libcgi-session-perl zip vim build-essential default-jre default-jdk ant make libhtml-scrubber-perl
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get install -y yarn

ENV FOSWIKI_LIBS /src/wiki-lib/lib/
ENV BUILD_PATH /build
ENV DEPLOY_PATH /deploy

RUN useradd -m builduser
RUN mkdir /src
RUN mkdir /build
RUN mkdir /deploy
RUN chmod -R 777 /src
RUN chmod -R 777 /build
RUN chmod -R 777 /deploy
USER builduser
RUN yarn config set cache-folder /home/builduser
RUN yarn global add bower@1.8.8 grunt@1.0.1 uglify-js@3.1.2
ENV PATH="/home/builduser/.yarn/bin:$PATH"

WORKDIR /src/
COPY --chown=builduser:builduser . .
RUN yarn
RUN yarn build

ENTRYPOINT node /src/dist/main.js
