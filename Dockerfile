ARG PG_VERSION=14.6
ARG VERSION=custom

FROM golang:1.16 as flyutil
ARG VERSION

WORKDIR /go/src/github.com/fly-examples/postgres-ha
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/flyadmin ./cmd/flyadmin
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/start ./cmd/start

RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-restart ./.flyctl/cmd/pg-restart
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-role ./.flyctl/cmd/pg-role
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-failover ./.flyctl/cmd/pg-failover
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/stolonctl-run ./.flyctl/cmd/stolonctl-run
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-settings ./.flyctl/cmd/pg-settings

COPY ./bin/* /fly/bin/

FROM flyio/stolon:327008e as stolon

FROM wrouesnel/postgres_exporter:latest AS postgres_exporter

FROM postgres:${PG_VERSION}
ARG VERSION 
ARG POSTGIS_MAJOR=3
ARG WALG_VERSION=2.0.0

LABEL fly.app_role=postgres_cluster
LABEL fly.version=${VERSION}
LABEL fly.pg-version=${PG_VERSION}

RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates curl bash dnsutils vim-tiny procps jq haproxy wget \
    && apt autoremove -y

RUN echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(cat /etc/os-release | grep VERSION_CODENAME | cut -d'=' -f2) main" > /etc/apt/sources.list.d/timescaledb.list \
    && curl -L https://packagecloud.io/timescale/timescaledb/gpgkey | apt-key add -

RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

RUN apt-get update && apt-get install --no-install-recommends -y \
    postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR} \
    postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}-scripts \
    timescaledb-2-postgresql-${PG_MAJOR} \
    postgresql-${PG_MAJOR}-pgrouting \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'Installing wal-g' \
    && curl -L https://github.com/wal-g/wal-g/releases/download/v${WALG_VERSION}/wal-g-pg-ubuntu-18.04-amd64 > /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g

COPY --from=stolon /go/src/app/bin/* /usr/local/bin/
COPY --from=postgres_exporter /postgres_exporter /usr/local/bin/

ADD /scripts/* /fly/
ADD /config/* /fly/
RUN useradd -ms /bin/bash stolon
RUN mkdir -p /run/haproxy/
COPY --from=flyutil /fly/bin/* /usr/local/bin/

ENV ENV="/fly/shell-init"

EXPOSE 5432

CMD ["start"]
