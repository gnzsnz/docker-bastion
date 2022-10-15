# SSH Bastion

This docker image will create an SSH bastion :japanese_castle:, with hardened default configuration.

The bastion container has the following features:

- Mount critical data as READ-ONLY.
- It creates hash signatures of passwd and sshd_config. Everytime the container is started it will validate signatures.
- Disabled TTY, it can only be used as a jump host a.k.a bastion.
- Implement sensible SSH hardened configuration
- Optional TOTP/MFA
- Support for SSH certificate authority (CA)

## Installation

To install SSH Bastion, you will need to clone the repository and set your preferences.

### Quick Start

```bash
git clone https://github.com/gnzsnz/docker-bastion.git
cp .env-dist .env
nano .env # edit env variables
cp docker-compose.yml-dist docker-compose.yml
nano docker-compose.yml # edit docker compose file
docker compose config # verify compose file
# set authorized keys, asuming bastion user
mkdir -p $PWD/data/home/bastion/.ssh
cp authorized_keys $PWD/data/home/bastion/.ssh
# run provision
docker run -it --rm -v $PWD/data:/data --env-file .env \
  gnzsnz/bastion /provision.sh
# start up your SSH bastion
docker compose up -d
```

Below you will find the options available.

## Setup

The following variables are available in the .env file

| Variable | default | Description |
| --- | --- | --- |
| APT_PROXY | blank | Defines an optional APT_PROXY to speed up image build. format -> http://aptproxy:3142 |
| SSH_LISTEN_PORT | 22222 | host external published port |
| USERS | bastion | Coma separated list of users, ex USERS=bastion,devops. Provisioning script will create users defined in this variable |
| USER_SHELL | /usr/sbin/nologin | mandatory, required to set user shell |
| BANNER_ENABLED | no | Enable SSH banner, by default display bastion_banner.tx. To change the banner you need to add a mount point `-v path/to/new_banner.txt:/bastion_banner.txt |
| TOTP_ENABLED | no | Enable TOTP, works with google authenticator or MS authenticator |
| TOTP_ISSUER | Bastion | Description for TOTP applciation |
| TOTP_QR_ENCODE | UTF8 | encoding for the TOTP URI QR, uses qrencoder |
| CA_ENABLED | 'no' | set to 'yes' to enable SSH CA mode |
| SSHD_HOST_CERT | '/etc/ssh/ssh_host_ed25519_key-cert.pub' | CA signed host certificate. You will need to copy it into ./data/etc/ssh directory |
| SSHD_USER_CA | '/etc/ssh/user_ca.pub' | public CA key. You will need to copy it into ./data/etc/ssh directory |
| IMAGE_VERSION |  | Used during build to tag the image. |
| BASE_VERSION | jammy | Ubuntu base image. Used during build. |

After you have set your .env file check that the configuration is correct

```bash
docker compose config
```

Make sure you set USERS variable with the users that will be using the SSH Bastion.

## Build the image

Optionally you can build the image with.

```bash
docker compose build
```

If defined APT_PROXY will be used during build time to speed up the build.

## Provision

Before you can use a container you need to provision the `./data` host directory with the necessary data. You need to run the provision script. Provision script will perform the following tasks

- create users, based on USERS env variable
- assign a shell to users, the purpose of a bastion is that users don't log-in, so leave `/usr/sbin/nologin` default unless you know what you are doing.
- sets data directory with:
  - /data/etc/passwd + shadow + group , based on users created
  - /data/etc/ssh/* , store ssh config and host keys
  - /data/home/*/.ssh/authorized_keys --> sets authorized_keys permissions
- create a provisioned hash signature
  - /etc/passwd + /etc/shadow + authorized_keys
  - /data/etc/ssh/bastion_provisioned_hash
- if `./data` bind mount is already provisioned it will use existing files

The container will mount all those files in read-only mode (unless you are using TOTP which requires write permissions in `/home`)

To set authorized keys, 

```bash
# create home folder
export USERS=devops,bastion
mkdir $PWD/data/home/{$USERS}/.ssh 
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/{$USERS}/.ssh 
```

This will copy pub keys for users devops and bastion.

Run provision mode

```bash
docker run -it --rm --env-file .env \
  -v $PWD/data:/data \
  gnzsnz/bastion /provision.sh
```

Once the provision script is run, data directory will have all the data required to run the container. Take into account that data directory owner and permissions will reflect data/etc/passwd UIDs and GIDs, you will need to sudo to make changes.

The provision script will create a hash signature, so if you modify data/etc content you might need to re-run the provision script.

## Run the container

Edit the docker-compose.yml file, the default values should work just fine. You can define a DNS or 'extra_hosts', this will allow SSH clients to use server names rather than IP addresses.

```yaml
version: "3.6"
services:
  bastion:
    build:
      context: .
      platforms:
        - "linux/amd64"
        - "linux/arm64"
        - "linux/arm/v7"
      args:
        APT_PROXY: ${APT_PROXY}
        BASE_VERSION: ${BASE_VERSION}
        IMAGE_VERSION: ${IMAGE_VERSION}
    image: gnzsnz/bastion:${IMAGE_VERSION}-${BASE_VERSION}
    restart: unless-stopped
    ports:
      - ${SSH_LISTEN_PORT}:22
    # optional
    # dns: ${DNS}
    #extra_hosts:
    #  - host 10.10.0.5 
    environment:
      - USERS=${USERS}
      - USER_SHELL=${USER_SHELL}
      - TOTP_ENABLED=${TOTP_ENABLED}
      - TOTP_ISSUER=${TOTP_ISSUER}
      - TOTP_QR_ENCODE=${TOTP_QR_ENCODE}
      - CA_ENABLED=${CA_ENABLED}
      - SSHD_HOST_CERT=${SSHD_HOST_CERT}
      - SSHD_USER_CA=${SSHD_USER_CA}
      - BANNER_ENABLED=${BANNER_ENABLED}
    volumes:
      - $PWD/data/etc/passwd:/etc/passwd:ro
      - $PWD/data/etc/shadow:/etc/shadow:ro
      - $PWD/data/etc/group:/etc/group:ro
      - $PWD/data/etc/ssh:/etc/ssh:ro
      - $PWD/data/home:/home:ro
```

Verify that everything has been set correctly (did you set .env file?)

```bash
docker compose config
```

When the container starts, it will

- Check for provisioned checksum
- Mount /etc/passwd + /etc/shadow + authorized_keys as READ-ONLY. This is to avoid modifications from within the container.

To run the container

```bash
docker compose up -d; docker-compose logs -f
```

If you modify data directory manually, you might need to run again the provision script. This will generate updated checksums that will pass validation during start-up.

## Add more users after the initial provision

To add more users or delete users, the easiest option is to edit your .env file, set USERS and run provision mode again. it will add to the existing /etc/passwd file and set the authorized keys.

You can add authorized_keys as explained before.

```bash
docker run -it --rm -e USERS=new_user,another_user \
  -v $PWD/data:/data \
  gnzsnz/bastion /provision.sh
```

## Client setup

Setup your `~/.ssh/config` file

```
### The Bastion Host
Host bastion-host-nickname
  HostName bastion-hostname
  AddKeysToAgent yes
  ForwardAgent yes

### The Remote Host
Host remote-host-nickname
  HostName remote-hostname
  ProxyJump bastion-host-nickname
  AddKeysToAgent yes
  ForwardAgent yes
```

To access `remote-hostname`, the bastion container should be able to translate the hostname to an IP address. Make sure your docker-compose.yml contains `extra_hosts` or a DNS entry

## Testing SSH bastion

You can now access your bastion

```bash
ssh -J devops@bastion_host:22222 devops@server
#  if you setup ~/.ssh/config ProxyJump
ssh devops@server
# scp
scp -J devops@bastion_host:22222 file.gz devops@server:/tmp
# port forwarding, take into account that forwarding is happening on server
# bastion is just a jump host
ssh -N -L 8888:localhost:80 -J devops@bastion_host:22222 devops@server
```

## Setting MFA/TOTP (Optional)

To set TOTP you need to edit `.env` file and set `TOTP_ENABLED=yes`. Optionally you can change the `TOTP_ISSUER=My-Bastion`. then you need to run the provision.sh script. It will create the credentials in the data/home/user_name directory.

If you enable TOTP, then `data/home` **CAN'T** be mounted as READ-ONLY as pam-google-authenticator needs to write in the user home directory.

Edit your docker-compose.yml file like this

```yaml
    volumes:
      - $PWD/data/etc/passwd:/etc/passwd:ro
      - $PWD/data/etc/shadow:/etc/shadow:ro
      - $PWD/data/etc/group:/etc/group:ro
      - $PWD/data/etc/ssh:/etc/ssh:ro
      - $PWD/data/home:/home # remove :ro
```

## Use a certificate authority

A certificate authority (CA) allows you to sign public keys (for hosts and users) and to verify signatures using the CA public key. This eliminates the need for known_hosts and authorized keys, all that you need is the host and user CA public key and to get your host and user keys signed.

You will need to manually copy your host certificate and public CA key into ./data/etc/ssh.

Make sure to set the CA_ENABLED variable, and set host cert and CA file names or copy the files using the default names.

## References

- Other bastion containers
  - https://github.com/panubo/docker-sshd/
  - https://github.com/binlab/docker-bastion/
  - https://github.com/fphammerle/docker-ssh-bastion/

- SSH hardening
  - https://infosec.mozilla.org/guidelines/openssh
  - https://www.ssh-audit.com/hardening_guides.html#ubuntu_20_04_lts
  - https://goteleport.com/blog/ssh-bastion-host/
  - https://goteleport.com/blog/security-hardening-ssh-bastion-best-practices/
  - https://news.ycombinator.com/item?id=29924053
