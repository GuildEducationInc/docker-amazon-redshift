# vim:set ft=dockerfile:
FROM debian:jessie

# explicitly set user/group IDs
RUN groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 postgres

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	&& apt-get purge -y --auto-remove ca-certificates wget

# Install
# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
ENV LANG en_US.utf8
ENV PGPORT 5439
ENV PGDATA /var/lib/postgresql/data
ENV PATH /usr/local/pgsql/bin:$PATH
ENV PG_MAJOR 8.0.2
ENV PG_MD5 62ca2786a4856c492fbdcd23bedb48c6

RUN apt-get update && apt-get install -y locales curl make gcc libreadline-dev zlib1g-dev libssl-dev \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
    && curl -O https://ftp.postgresql.org/pub/source/v$PG_MAJOR/postgresql-$PG_MAJOR.tar.gz \
    && echo "$PG_MD5 *postgresql-$PG_MAJOR.tar.gz" | md5sum -c - \
    && tar xf postgresql-$PG_MAJOR.tar.gz \
    && cd postgresql-$PG_MAJOR \
    && ./configure \
      --enable-integer-datetimes \
      --enable-thread-safety \
      --enable-tap-tests \
      --disable-rpath \
      --with-uuid=e2fs \
      --with-pgport=$PGPORT \
      --with-system-tzdata=/usr/share/zoneinfo \
      --prefix=/usr/local \
      --with-includes=/usr/local/include \
      --with-libraries=/usr/local/lib \
      --with-openssl \
      --with-libxml \
      --with-libxslt \
    && make && make install \
    && rm -rf postgresql-$PG_MAJOR* /usr/local/share/man \
    && apt-get purge -y --auto-remove curl make gcc \
    && find /usr/local -name '*.a' -delete \
    && rm -rf /var/lib/apt/lists/*

# make the sample config easier to munge (and "correct by default")
RUN sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/local/share/postgresql/postgresql.conf.sample \
	&& sed -ri "s!^#?(port)\s*=\s*\S+.*!\1 = ${PGPORT}!" /usr/local/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA" # this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
VOLUME /var/lib/postgresql/data

# Entrypoint
RUN mkdir /docker-entrypoint-initdb.d
COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh / # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 5439
CMD ["postmaster"]
