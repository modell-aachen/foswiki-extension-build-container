FROM node:8.16.2-jessie

RUN rm -f /etc/localtime \
    && ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime \
    && apt-get update \
    && apt-get install -y \
            ant \
            apt-transport-https \
            build-essential \
            cpanminus \
            curl \
            default-jdk \
            default-jre \
            libcairo2-dev \
            libcgi-pm-perl \
            libcgi-session-perl \
            libcss-minifier-perl \
            libgif-dev \
            libhtml-scrubber-perl \
            libjavascript-minifier-perl \
            libjpeg-dev \
            libjson-perl \
            libpango1.0-dev \
            librsvg2-dev \
            libthread-pool-simple-perl \
            make \
            vim \
            zip \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367 \
    && echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" | tee /etc/apt/sources.list.d/ansible.list \
    && apt-get update && apt-get install -y yarn ansible

RUN cpanm --notest Redis

ENV FOSWIKI_LIBS /src/wiki-lib/lib/
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
RUN yarn global add bower@1.8.8 grunt@1.0.1 uglify-js@3.1.2
ENV PATH="/home/builduser/.yarn/bin:$PATH"

WORKDIR /src/
COPY --chown=builduser:builduser . .
RUN yarn \
    && yarn build

ENTRYPOINT HOME=/home/builduser node /src/dist/main.js
