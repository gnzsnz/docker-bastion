#!/usr/bin/env bash
###############################################################################
# entrypoint.sh
#
# sshd bastion
#
# entrypoint script for sshd bastion docker image. it starts sshd by default,
# takes '-o' sshd option parameters. or run a command in container, ex: 
# docker run -it gnzsnz/bastion bash
#
###############################################################################

set -e

DAEMON=sshd
PROVISON=/etc/ssh/bastion_provisioned_hash
SSHD_OPT=''

stop() {
    echo "> Received SIGINT or SIGTERM. Shutting down $DAEMON"
    # Get PID
    local pid
    pid=$(cat /var/run/$DAEMON.pid)
    # Set TERM
    kill -SIGTERM "${pid}"
    # Wait for exit
    wait "${pid}"
    # All done.
    echo "> Done... $?"
}

check_provision() {

  if [ ! -f $PROVISON ]; then
    echo "> Container not provisioned."
    exit 1
  elif sha256sum -c $PROVISON ; then
    echo "> 🔑 checksum valid."
  else
    echo "> checksum FAILED. 🔒 exiting ..."
    echo "> You might want to provision your data/ dir
    docker run -it --rm --env-file .env \
      --hostname=sftp \
      -v $PWD/data:/data \
      --name sftp_provision \
      gnzsnz/sftp /provision.sh
    "
    exit 1
  fi
}

bastion_banner() {
  # show banner
  if [ "$BANNER_ENABLED" == "yes" ]; then
    SSHD_OPT+=" -o Banner=/bastion_banner.txt"
    echo "> Banner enabled"
    cat /bastion_banner.txt
  else
    echo "> Banner disabled"
  fi
}

set_totp() {
  #
  # set TOTP sshd paramenters in variable SSHD_OPT
  #
  if [ "$TOTP_ENABLED" == "yes" ] ; then
    SSHD_TOTP=' -o KbdInteractiveAuthentication=yes'
    SSHD_TOTP+=' -o AuthenticationMethods=publickey,keyboard-interactive'
    SSHD_TOTP+=' -o UsePAM=yes'
    SSHD_OPT+=$SSHD_TOTP
    echo "> TOTP ⌛🔑 enabled"
  else
    echo "> TOTP ⌛🔑 disabled"
  fi
}

set_CA() {
  #
  # set CA parameters in SSHD_OPT variable
  #
  if [ "$CA_ENABLED" == "yes" ] ; then
    # set host certificate
    [ ! -f "$SSHD_HOST_CERT" ] && SSHD_HOST_CERT='/etc/ssh/ssh_host_ed25519_key-cert.pub'
    SSHD_CA=" -o HostCertificate=$SSHD_HOST_CERT"
    # set user CA public key
    [ ! -f "$SSHD_USER_CA" ] && SSHD_USER_CA='/etc/ssh/user_ca.pub'
    SSHD_CA+=" -o TrustedUserCAKeys=$SSHD_USER_CA"

    # add to SSHD options
    SSHD_OPT+=$SSHD_CA
    echo "> SSH CA 🔏 enabled"
  else
    echo "> SSH CA 🔏 disabled"
  fi    
}

echo "> SSH Bastion 🐡🏯"
echo "> Running $*"
if [ "$(basename "$1")" == "$DAEMON" ]; then
  check_provision
  set_totp
  set_CA
  bastion_banner
  lslogins
  echo "> Starting $* ... $SSHD_OPT"
  trap stop SIGINT SIGTERM
  "$@" ${SSHD_OPT} &
  pid="$!"
  echo "> $DAEMON pid: $pid"
  wait "${pid}"
  exit $?
elif echo "$*" | grep ^-o ; then
  # accept parameters from command line or compose
  check_provision
  set_totp
  set_CA
  bastion_banner
  lslogins
  echo "> Starting $* ... $SSHD_OPT"
  trap stop SIGINT SIGTERM
  /usr/sbin/sshd -D -e "$@" ${SSHD_OPT} &
  pid="$!"
  echo "> $DAEMON pid: $pid"
  wait "${pid}"
  exit $?
else
  # run command from docker run
  exec "$@"
fi
