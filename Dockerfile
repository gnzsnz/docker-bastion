ARG BASE_VERSION
FROM ubuntu:${BASE_VERSION:-latest}

ARG BASE_VERSION
ARG APT_PROXY
ARG IMAGE_VERSION
RUN if [ -n "$APT_PROXY" ]; then \
      echo 'Acquire::http { Proxy "'$APT_PROXY'"; }'  \
      | tee /etc/apt/apt.conf.d/01proxy \
    ;fi && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    openssh-server libpam-google-authenticator qrencode libssl3 libcrypt1 && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /run/sshd && \
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config-dist && \
    awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.secure && \
    mv /etc/ssh/moduli.secure /etc/ssh/moduli && \
    groupadd -g 59999 ssh-bastion && \
    cp /etc/pam.d/sshd /etc/pam.d/sshd.back && \
    grep -v "include common-auth" /etc/pam.d/sshd.back > /etc/pam.d/sshd && \
    echo "# TOTP\nauth required pam_google_authenticator.so nullok\nauth"\
    "required pam_permit.so" >> /etc/pam.d/sshd && \
    rm /etc/ssh/ssh_host_*key*

COPY sshd_config /etc/ssh/
COPY sntrup761.conf-dist /etc/ssh/sshd_config.d/sntrup761.conf-dist
COPY entrypoint.sh /
COPY provision.sh /
COPY bastion_banner.txt /

RUN if [ $(grep 'jammy' < /etc/lsb-release) ]; then  \
	mv /etc/ssh/sshd_config.d/sntrup761.conf-dist /etc/ssh/sshd_config.d/sntrup761.conf ;\
    fi

HEALTHCHECK --interval=30m --timeout=15s --start-period=10s \
  CMD timeout 1 bash -c '</dev/tcp/0.0.0.0/22 && echo "SSH Bastion running" || echo "Port is closed"' || echo "Connection timeout"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]

LABEL org.opencontainers.image.source=https://github.com/gnzsnz/docker-bastion.git
LABEL org.opencontainers.image.url=https://hub.docker.com/r/gnzsnz/bastion
LABEL org.opencontainers.image.description="OpenSSH Bastion container"
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.version=${IMAGE_VERSION}-${BASE_VERSION}
