# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG WINE_BRANCH=stable
ARG WINETRICKS_VERSION=20240105
ARG MT_UID=1000
ARG MT_GID=1000

# TZ affects local logs and TimeLocal() in MQL.
# EAs using TimeCurrent() follow broker server time.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=America/Sao_Paulo \
    DISPLAY=:99 \
    WINEDEBUG=-all \
    MALLOC_ARENA_MAX=2 \
    PATH="/opt/mt/bin:${PATH}"

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget gnupg software-properties-common; \
    add-apt-repository -y universe; \
    mkdir -pm755 /etc/apt/keyrings; \
    wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key; \
    wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "winehq-${WINE_BRANCH}" wine32 wine64 \
        xvfb x11vnc x11-utils fluxbox \
        novnc websockify supervisor \
        cabextract unzip p7zip-full \
        procps tzdata fonts-liberation; \
    ln -sf vnc.html /usr/share/novnc/index.html; \
    apt-get purge -y software-properties-common; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*

RUN wget -qO /usr/local/bin/winetricks \
      "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks" && \
    head -n1 /usr/local/bin/winetricks | grep -q '^#!' && \
    chmod 755 /usr/local/bin/winetricks

RUN groupadd -g "${MT_GID}" mt && \
    useradd -m -u "${MT_UID}" -g mt -s /bin/bash mt && \
    mkdir -p /home/mt/prefix/mt4 /home/mt/prefix/mt5 /home/mt/logs /home/mt/installers /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix && \
    chown -R mt:mt /home/mt

COPY docker/bin/ /opt/mt/bin/
COPY docker/lib/ /opt/mt/lib/
COPY docker/supervisord.conf /etc/supervisor/mt.conf
RUN chmod 755 /opt/mt/bin/* && chmod 644 /opt/mt/lib/common.sh /etc/supervisor/mt.conf

USER mt
WORKDIR /home/mt
EXPOSE 6080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/opt/mt/bin/mt-entrypoint"]
