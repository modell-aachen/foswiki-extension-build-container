FROM node:8.15.1-stretch

ENV FOSWIKI_LIBS /usr/src/wiki-lib/lib/
ENV BUILD_PATH /build
ENV DEPLOY_PATH /deploy

WORKDIR /usr/src/

RUN mkdir /build
RUN mkdir /deploy
RUN apt-get update
RUN apt-get install -y apt-transport-https curl libcss-minifier-perl libjavascript-minifier-perl libjson-perl libcgi-session-perl zip vim build-essential default-jre default-jdk ant make
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get install -y yarn

COPY . .
RUN yarn build

ENTRYPOINT yarn start