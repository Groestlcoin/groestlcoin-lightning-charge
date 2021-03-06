FROM node:12.16-slim as builder

ARG STANDALONE=1

RUN mkdir /opt/local && apt-get update && apt-get install -y --no-install-recommends git gpg dirmngr ca-certificates wget \
    $([ -n "$STANDALONE" ] || echo "autoconf automake build-essential gettext libtool libgmp-dev \
                                     libsqlite3-dev python python3 python3-mako zlib1g-dev")

ARG TESTRUNNER
ARG LIGHTNINGD_VERSION=master

RUN [ -n "$STANDALONE" ] || \
    (git clone https://github.com/groestlcoin/lightning.git /opt/lightningd \
    && cd /opt/lightningd \
    && git checkout $LIGHTNINGD_VERSION \
    && DEVELOPER=$TESTRUNNER ./configure --prefix=./target \
    && make \
    && make install \
    && rm -r target/share \
    && mv -f target/* /opt/local/)

ENV GROESTLCOIN_VERSION 2.20.1
ENV GROESTLCOIN_FILENAME groestlcoin-$GROESTLCOIN_VERSION-x86_64-linux-gnu.tar.gz
ENV GROESTLCOIN_URL https://github.com/Groestlcoin/groestlcoin/releases/download/v$GROESTLCOIN_VERSION/$GROESTLCOIN_FILENAME
ENV GROESTLCOIN_SHA256 0a877be9dac14f4d9aab95d6bfd51547275acbcc3e6553f0cb82c5c9f35f333c
ENV GROESTLCOIN_ASC_URL https://github.com/Groestlcoin/groestlcoin/releases/download/v$GROESTLCOIN_VERSION/SHA256SUMS.asc
ENV GROESTLCOIN_PGP_KEY 287AE4CA1187C68C08B49CB2D11BD4F33F1DB499
RUN [ -n "$STANDALONE" ] || \
    (mkdir /opt/groestlcoin && cd /opt/groestlcoin \
    && wget -qO "$GROESTLCOIN_FILENAME" "$GROESTLCOIN_URL" \
    && echo "$GROESTLCOIN_SHA256 $GROESTLCOIN_FILENAME" | sha256sum -c - \
    && for server in $(shuf -e ha.pool.sks-keyservers.net \
                             hkp://p80.pool.sks-keyservers.net:80 \
                             keyserver.ubuntu.com \
                             hkp://keyserver.ubuntu.com:80 \
                             pgp.mit.edu) ; do \
         gpg --batch --keyserver "$server" --recv-keys "$GROESTLCOIN_PGP_KEY" && break || : ; \
       done \
    && wget -qO groestlcoin.asc "$GROESTLCOIN_ASC_URL" \
    && gpg --verify groestlcoin.asc \
    && cat groestlcoin.asc | grep "$GROESTLCOIN_FILENAME" | sha256sum -c - \
    && BD=groestlcoin-$GROESTLCOIN_VERSION/bin \
    && tar -xzvf "$GROESTLCOIN_FILENAME" $BD/groestlcoind $BD/groestlcoin-cli --strip-components=1 \
    && mv bin/* /opt/local/bin/)

RUN wget -qO /usr/bin/tini "https://github.com/krallin/tini/releases/download/v0.19.0/tini-amd64" \
    && echo "93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c /usr/bin/tini" | sha256sum -c - \
    && chmod +x /usr/bin/tini

WORKDIR /opt/charged

COPY package.json npm-shrinkwrap.json ./
RUN npm install \
   && test -n "$TESTRUNNER" || { \
      cp -r node_modules node_modules.dev \
      && npm prune --production \
      && mv -f node_modules node_modules.prod \
      && mv -f node_modules.dev node_modules; }

COPY . .
RUN npm run dist \
    && rm -rf src \
    && test -n "$TESTRUNNER" || (rm -rf test node_modules && mv -f node_modules.prod node_modules)

FROM node:12.16-slim

WORKDIR /opt/charged
ARG TESTRUNNER
ENV HOME /tmp
ENV NODE_ENV production
ARG STANDALONE
ENV STANDALONE=$STANDALONE

RUN apt-get update \
    && apt-get install -y --no-install-recommends inotify-tools \
    && ([ -n "$STANDALONE" ] || apt-get install -y --no-install-recommends libgmp-dev libsqlite3-dev) \
    && ([ -z "$TESTRUNNER" ] || apt-get install -y --no-install-recommends jq procps curl) \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /opt/charged/bin/charged /usr/bin/charged \
    && mkdir /data \
    && ln -s /data/lightning /tmp/.lightning

COPY --from=builder /opt/local /usr/local
COPY --from=builder /opt/charged /opt/charged
COPY --from=builder /usr/bin/tini /usr/bin/

ENTRYPOINT [ "tini", "-g", "--", "bin/docker-entrypoint.sh" ]
EXPOSE 9112 9735
