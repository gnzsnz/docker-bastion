# SSH Bastion

Dockerized SSH bastion :japanese_castle:, with hardened defaults. An SSH bastion is a jump server accessible from the Internet that gives access to services in a private network. Once a bastion is in place you can access private network services through it.

Features:

- Implement sensible hardened SSH configuration
- Mount critical data as READ-ONLY.
- It creates hash signatures of passwd and sshd_config. Every time the container is started it will validate signatures.
- Disabled TTY, it can only be used as a jump host a.k.a bastion.
- Optional TOTP/MFA
- Support for SSH certificate authority (CA)
- Support for scp, sftp, rsync, port forwarding through bastion and from/to bastion.
- Fully customizable.

## Quick start

Follow the steps below to have a running SSH bastion:

- Create a [docker-compose.yml](https://github.com/gnzsnz/docker-bastion/blob/master/docker-compose.yml-dist) file. See [example](#Run-the-container) below
- Create an [.env](https://github.com/gnzsnz/docker-bastion/blob/master/.env-dist) file. See available [options](#setup).
- Copy `authorized_keys` file in `data` folder. We will create two users and asume they already have authorized keys in `/home/user_name/.ssh/autorized_keys`

```bash
# create home folder
export USERS=devops,bastion
mkdir $PWD/data/home/{$USERS}/.ssh
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/{$USERS}/.ssh
```

- Provision the `data` folder. This is required to create the folder structure required by SSH bastion. See more details on [provisioning](#provision)

```bash
docker run -it --rm --env-file .env \
  -v $PWD/data:/data \
  gnzsnz/bastion /provision.sh
```

- We are ready to go

```bash
docker compose up
```

- Test your setup. See more [examples](#ssh-bastion-use-cases) below

```bash
ssh -J devops@bastion:22222 devops@remote_host
```

This is telling ssh to create an ssh connetion to the server specified with parameter `-J`, in this case `devops@bastion:22222` and once it's connected create another connection from `bastion` to `remote_host`. From the client's point of view, it looks like a direct connection to `remote_host`

### All the steps together

We will clone the git repository to use it as a template and set our preferences.

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
docker compose up -d && docker compose logs -ft
```

Below you will find the available [environment variables](#environment-variables), how to [build](#build-the-image) the image, more details on the [provisioning](#provision) process, running a [bastion container](#run-the-container), managing [user access](#user-access), how to setup your [ssh clinets](#client-setup), the many [use cases](#ssh-bastion-use-cases) for an SSH bastion, [multi-factor](#setting-mfatotp-optional) authentication or MFA/TOTP and certificate authorities [CA](#use-a-certificate-authority). Enjoy the reading.

## Environment variables

The following variables are available in the .env file

| Variable | default | Description |
| --- | --- | --- |
| APT_PROXY | blank | Defines an optional APT_PROXY to speed up image build. format -> http://aptproxy:3142. You can try [apt-cacher-ng](https://github.com/gnzsnz/apt-cacher-ng) |
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

After you have set your .env file check that the configuration is correct.

```bash
docker compose config
```

Make sure you set `USERS` variable with the users that will be using the SSH Bastion.

In addition to environment variables, you can modify the behavior of SSH bastion by passing command line arguments or setting the configuration file. See section [Run the container](#run-the-container) for more details.

## Build the image

Optionally you can build the image by following the steps below.

```bash
docker compose build
```

If defined `APT_PROXY` will be used during build time to speed up the build.

You can find ready-to-use bastion images in [docker hub](https://hub.docker.com/r/gnzsnz/bastion) and [github container registry](https://github.com/gnzsnz/docker-bastion/pkgs/container/bastion). The docker compose file provided as an example will pull the image from docker hub.

## Provision

Before you can use a container you need to provision the `./data` host directory with the necessary data. This can be acomplished by running the provision script. The `/data` directory contains all the config needed by SSH, host and user keys plus user access. Provision script will perform the following tasks:

- create users, based on `USERS` env variable
- assign a shell to users, by definition users don't log into a SSH bastion, so leave `/usr/sbin/nologin` default unless you know what you are doing.
- sets data directory with:
  - /data/etc/passwd + shadow + group , based on users created
  - /data/etc/ssh/* , store ssh config and host keys
  - /data/home/*/.ssh/authorized_keys --> sets authorized_keys permissions
- Create a provisioned hash signature
  - /etc/passwd + /etc/shadow + authorized_keys
  - /data/etc/ssh/bastion_provisioned_hash
  - signatures are verified on every start by entrypoint script.
- If `./data` bind mount is already provisioned it will use existing files

The container will mount all those files in read-only mode (unless you are using TOTP which requires write permissions in `/home`)

To set authorized keys,

```bash
# create home folder
export USERS=devops,bastion
mkdir $PWD/data/home/{$USERS}/.ssh
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/{$USERS}/.ssh
```

This will copy pub keys for user `devops` and `bastion`.

Run provision script

```bash
docker run -it --rm --env-file .env \
  -v $PWD/data:/data \
  gnzsnz/bastion /provision.sh
```

Once the provision script is run, data directory will have all the data required to run the container. Take into account that data directory owner and permissions will reflect data/etc/passwd UIDs and GIDs, you will need `sudo` to make changes.

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
    # command: ["-o ForwardX11=yes "]
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

If you modify the data directory manually, you might need to run again the provision script. This will generate updated checksums that will pass validation during start-up.

You can change the behavior of bastion by setting parameters on the command line or `command` element in `docker-compose.yml` any valid [sshd](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html) option will work. The sample docker file above includes a line to allow X forwarding --> `command: ["-o ForwardX11=yes "]`.

Another option is to include additional configuration in `/data/etc/ssh/sshd_config.d/` as bastion will read those files.

## User Access

Bastion follows OpenSSH [authentication](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html#authentication). Typically you need to setup user `authorized_keys` file with the public key for each user. A simpler approach for managing `authorized_keys` file point of view is to set up a certificate authority (CA). This requires extra steps to generate and manage the certificates but does not require a line in `authorized_keys` file, nor a `known_host` record for each host. See the section on [certificate authorities](#use-a-certificate-authority).

To add more users, the easiest option is to edit your .env file, set USERS and run provision mode again. It will add to the existing /etc/passwd file and set the authorized keys.

```bash
docker run -it --rm -e USERS=new_user,another_user \
  -v $PWD/data:/data \
  gnzsnz/bastion /provision.sh
```

Disable existing users

```bash
docker run -it --rm -v $PWD/data:/data \
  gnzsnz/bastion adduser --disable-login user_name
```

You can add authorized_keys as explained in [provision](#provision) section.

## SSH bastion use cases

If you have followed this README, by now you should have an SSH bastion container up and running. You can now access your ssh servers through bastion

Let's start with a simple case, you open a connection using `-J` option, or you setup you ssh [config](#client-setup) stating that you connect to `server` through a `ProxyJump`.

```bash
ssh -J devops@bastion_host:22222 devops@server
#  if you setup ~/.ssh/config ProxyJump
ssh devops@server
```

We can also do scp, rsync, sftp, port forwarding or a socks proxy

```bash
# scp
scp -J devops@bastion_host:22222 file.gz devops@server:/tmp
# no need to use -J if you use ProxyJump in config file
scp file.gz devops@server:/tmp

# same for rsync
rsync -rtva devops@server:/tmp/file.gz /tmp

# sftp
sftp -J devops@bastion_host:22222 file.gz devops@server:/tmp
sftp file.gz devops@server:/tmp
sftp devops@server

# port forwarding, take into account that forwarding is happening on server
# bastion is just a jump host
ssh -N -L 8888:localhost:80 -J devops@bastion_host:22222 pgsql.example.com
# and without -J
ssh -N -L 8888:localhost:80 devops@pgsql.example.com
# remote forward, ex forward local:80 to remote's localhost:8888
ssh -N -R 80:localhost:8888 devops@app.example.com

# if you setup local or remote forward in your config, then you just do
ssh rf_app
ssh lf_app

# socks proxy
ssh -J devops@bastion_host:22222 -D 1337 -f -N devops@server.example.com
ssh myproxy
```

See next section with examples for [client setup](#client-setup).

A special case that might deserver additional attention is as a *sidecar container* for port forwarding

```
             >|<   _____________
__________    |    | Bastion   |      
| Client | ---|--- | Container | ----\ 
----------    |    -------------     | 
              |     _____________    |
              |     | App       | ---/
              |     | Container |
              |     -------------
              |
             >|<                      

App to Bastion: ssh -R 8888:localhost:8888 bastion
Client to Bastion: ssh -L 8888:localhost:8888 bastion
```

In the scenario above, our App needs to expose port 8888 however, it's not secure to do so (VNC). In the App container, we can install an ssh client that will create a remote forward on the ssh bastion. While the client will create a local forward. Notice that in this case we are actually connecting to the bastion, we are not using it as a ProxyJump. This is allowed because we are not opening a shell session.

In this scenario, we don't need to install an sshd server in the app container just an ssh client. The only port that needs to be exposed to the internet is the bastion port. With proper ssh client configuration it's both forward connections are easy to setup. The App container can focus on doing what it does best, and the bastion container can create secure connections.

## Client setup

You can setup your `~/.ssh/config` file to simplify your client commands

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

# remote forward example
Host rf_app
  Hostname app.example.com
  ProxyJump bastion-host-nickname
  # local_host:local_port:remote_host:remote_port
  # local is from ssh client point of view, remote is any host accessible for ssh server
  RemoteForward localhost:5432 localhost:5432
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

# local forward example
Host lf_pgsql
  Hostname pgsql.example.com
  ProxyJump jump_host_nickname
  # local_host:local_port:remote_host:remote_port
  # local is from ssh client point of view, remote is any host accessible for ssh server
  LocalForward localhost:5432 localhost:5432
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

# socks dynamic proxy example
Host myproxy
  Hostname server.example.com
  Port 2222
  ProxyJump bastion-host-nickname
  DynamicForward 1337
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

Host *.local 10.0.0.*
  ProxyJump bastion-host-nickname
#  ForwardAgent yes
#  UseKeychain yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519
```

To access `remote-hostname`, the bastion container should be able to translate the hostname to an IP address. Make sure your docker-compose.yml contains `extra_hosts` or a DNS entry.

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

A certificate authority (CA) allows you to sign public keys (for hosts and users) and to verify signatures using the CA public key. This eliminates the need for known_hosts and authorized keys, all that you need is the host and user CA public key and to get your host and user public keys signed.

You will need to manually copy your host certificate and public CA key into ./data/etc/ssh.

Make sure to set the CA_ENABLED variable, and set host cert and CA file names or copy the files using the default names.

## Additional security

You will probably want to pair SSH bastion with fail2ban or a fail2ban container.

## References

- OpenSSH
  - [sshd](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html)
  - [sshd_config](https://manpages.ubuntu.com/manpages/jammy/en/man5/sshd_config.5.html)
  - [ssh](https://manpages.ubuntu.com/manpages/jammy/en/man1/ssh.1.html)
  - [ssh_config](https://manpages.ubuntu.com/manpages/jammy/en/man5/ssh_config.5.html)
  - [ssh-keygen](https://manpages.ubuntu.com/manpages/jammy/en/man1/ssh-keygen.1.html)

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
