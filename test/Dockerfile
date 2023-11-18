ARG BASE_VERSION
FROM ubuntu:${BASE_VERSION}

ARG BASE_VERSION
ARG USER_ID=1000
ARG USER_GID=1000
ARG USER=bastion
ARG APT_PROXY=
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN if [ -n "${APT_PROXY}" ]; then \
      echo 'Acquire::http { Proxy "'${APT_PROXY}'"; }'  \
      | tee /etc/apt/apt.conf.d/01proxy \
    ;fi && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      --no-install-recommends openssh-server openssh-client && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /run/sshd && \
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config-dist && \
    awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.secure && \
    mv /etc/ssh/moduli.secure /etc/ssh/moduli && \
    groupadd --gid "${USER_GID}" "${USER}" && \
    useradd -ms /bin/bash --uid ${USER_ID} --gid ${USER_GID} ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers && \
    mkdir /home/${USER}/.ssh && \
    ssh-keygen -N "" -f /home/${USER}/.ssh/id_rsa && \
    ssh-keygen -N "" -t ed25519 -f /home/${USER}/.ssh/id_ed25519 && \
    cat /home/${USER}/.ssh/id_rsa.pub >> /home/${USER}/.ssh/authorized_keys && \
    cat /home/${USER}/.ssh/id_ed25519.pub >> /home/${USER}/.ssh/authorized_keys && \
    chown ${USER}:${USER} /home/${USER}/.ssh/id_* && \
    chown ${USER}:${USER} /home/${USER}/.ssh/authorized_keys
VOLUME ["/home/${USER}/.ssh"]
