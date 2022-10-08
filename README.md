# SSH Bastion

This docker image will create an SSH bastion :japanese_castle:, with hardened default config.

The bastion container has the following features:
- mount critical data as READ-ONLY.
- it create hash signatures of passwd and sshd_config. Everytime the container is stared it will validate signatures.
- disabled TTY, it can only be used as a jump host a.k.a bastion.
- implement sensible SSH hardened configuration
- optional TOTP/MFA
- support for SSH certificate authority (CA)

## Instalation

In order to install SSH Bastion you will need to clone the repository and set your preferences
```bash
git clone https://github.com/gnzsnz/docker-bastion.git
cp .env-dist .env
nano .env # edit env variables
nano docker-compose.yml # edit docker compose file
```
Below you will find the options available.

## Setup

Set variables in .env file

| Variable | default | Description |
| --- | --- | --- |
| APT_PROXY | blank -> '' | defines an optional APT_PROXY to speed up image build. format -> http://aptproxy:3142 |
| SSH_LISTEN_PORT | 22222 | host external published port |
| SSH_INNER_PORT | 22 | container port |
| USERS | bastion | List of users, ex USERS=bastion,devops. provisioning script will create users in this variable |
| USER_SHELL | /usr/sbin/nologin | mandatory, required to set user shell |
| TOTP_ENABLED | no | Enable TOTP, works with google authenticator or MS authenticator |
| TOTP_ISSUER | Bastion | Description for TOTP applciation |
| TOTP_QR_ENCODE | UTF8 | encoding for the TOTP URI QR, uses qrencoder |
| CA_ENABLED | 'no' | set to 'yes' to enable SSH CA mode |
| SSHD_HOST_CERT | '/etc/ssh/ssh_host_ed25519_key-cert.pub' | CA signed host certificate. You will need to copy it into ./data/etc/ssh directory |
| SSHD_USER_CA | '/etc/ssh/user_ca.pub' | public CA key. You will need to copy it into ./data/etc/ssh directory |


## Build the image

To build the image
```bash
docker-compose build
```
APT_PROXY will be used during build time to speed up build.

## Provision

Before you can use a container you need to provision the `./data` host directory with the necessary data. You need to run the provision script. Provision scrip will perform the following tasks
- create users, based on USERS env variable
- assign a shell to users, the pourpose of a bastion is that users don't loging, so leave `/usr/sbin/nologin` default unless you know what you are doing.
- sets data directory with:
  - /data/etc/passwd + shadow + group , based on users created
  - /data/etc/ssh/* , store ssh config and host keys
  - /data/home/*/.ssh/authorized_keys --> sets authorized_keys permissions
- create a provisioned hash signature
  - /etc/passwd + /etc/shadow + authorized_keys
  - /data/etc/ssh/bastion_provisioned_hash
- if `./data` bind mount is already provisioned it will use existing files

The continer will mount all those files in read-only mode (unless you are using TOTP which requires to write in `/home`)

To set authorized keys, in this case DATA=$PWD/data
```bash
# create home folder
mkdir $PWD/data $PWD/data/home
USERS=devops,bastion mkdir $PWD/data/home/{$USERS} $PWD/data/home/{$USERS}/.ssh 
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/{$USERS}/.ssh 
```

This will copy pub keys for users devops and bastion.

Run provision mode
```bash
docker run -it --rm --env-file .env \
  --hostname=bastion \
  -v $PWD/data:/data \
  --name bastion_provision \
  gnzsnz/bastion:202208 /provision.sh
```

The provision container can be deleted after data directory is provisioned. Once provision script is run, data directory will have all the data required to run the container. Take into account that data directory owner and permissions will reflect data/etc/passwd UIDs and GIDs, you will need to sudo to make changes.

Provision script will create a has signature, so if you modify data/etc content you might need to re-run the provision script.s

## Run the container

Edit the docker-compose.yml file, the default should work just fine

```yaml
version: "3.6"
services:
  bastion:
    build:
      context: .
      args:
        APT_PROXY: $APT_PROXY
    image: gnzsnz/bastion:202208
    container_name: bastion
    hostname: bastion
    restart: unless-stopped
    ports:
      - $SSH_LISTEN_PORT:$SSH_INNER_PORT
    environment:
      - USERS=$USERS
      - USER_SHELL=$USER_SHELL
      - TOTP_ENABLED=$TOTP_ENABLED
      - TOTP_ISSUER=$TOTP_ISSUER
      - TOTP_QR_ENCODE=$TOTP_QR_ENCODE
      - CA_ENABLED=$CA_ENABLED
      - SSHD_HOST_CERT=$SSHD_HOST_CERT
      - SSHD_USER_CA=$SSHD_USER_CA
    volumes:
      - $PWD/data/etc/passwd:/etc/passwd:ro
      - $PWD/data/etc/shadow:/etc/shadow:ro
      - $PWD/data/etc/group:/etc/group:ro
      - $PWD/data/etc/ssh:/etc/ssh:ro
      - $PWD/data/home:/home:ro
```

Verify that everything has been set correctly (did you set .env file?)
```bash
docker-compose config
```

When the container starts, it will
 - check for provisioned checksum
 - mount /etc/passwd + /etc/shadow + authorized_keys as READ-ONLY. This is to avoid modifications from within the container.

To run the container
```bash
docker-compose up -d; docker-compose logs -f
```

If you modify data directory manually, you might need to run again the provision script. This will generate updated checksums that will pass validation during start-up.

## Add more users after initial provision

To add more users or delete users, the easiest option is to edit your .env file, set USERS and run provision mode again. it will add to the existing /etc/passwd file and set the authorized keys.

You can add authorized_keys as explained before.

```bash
docker run -it --rm -e USERS=new_user,another_user \
  - e USER_SHELL=/usr/sbin/nologin
  --hostname=bastion \
  -v $PWD/data:/data \
  --name bastion_provision \
  gnzsnz/bastion:202208 /provision.sh
```

## Client setup

Setup your `~/.ssh/config`
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
## Testing SSH bastion

You can now access your bastion
```bash
ssh -J devops@bastion_host:22222 devops@server
# only if you setup ~/.ssh/config ProxyJump
ssh devops@server
scp file.gz devops@server:/tmp
ssh -N -L 8888:localhost:80 devops@server
```
## Setting MFA/TOTP (Optional)

To set TOTP you need to edit `.env` file and set `TOTP_ENABLED=yes`. Optionally you can change the `TOTP_ISSUER=My-Bastion`. then you need to run the provision.sh script. It will create the credentials in the data/home/user_name directory.

If you enable TOTP, then data/home **CAN'T** be mounted as READ-ONLY. pam-google-authenticator needs to write in the user home directory.

Edit your docker-compose.yml file like this

```yaml
    volumes:
      - $PWD/data/etc/passwd:/etc/passwd:ro
      - $PWD/data/etc/shadow:/etc/shadow:ro
      - $PWD/data/etc/group:/etc/group:ro
      - $PWD/data/etc/ssh:/etc/ssh:ro
      - $PWD/data/home:/home # remove :ro
```

## Use LDAP for authorized keys storge

Usually you would store public keys in `~/.ssh/authorized_keys`, this comes with disadvantges. Each user needs to move around their authorized keys with 

http://pig.made-it.com/ldap-openssh.html
https://warlord0blog.wordpress.com/2020/05/16/ssh-authorized_keys-and-ldap/

https://openssh-ldap-pubkey.readthedocs.io/en/latest/openldap.html

## Use a certificate authority

A certificate authority (CA) alows you to sign public keys (for hosts and users) and to verify signagures using the CA public key. This eliminates completelly the need of known_hosts and authorized keys, all that you need is the host and user CA public key and to get your host and user keys signed.

you will need to manually copy your host certificate and public CA key into ./data/etc/ssh.

Make sure to set the the CA_ENABLED variable, and set host cert and CA file names or copy the files using the default names.

# References

https://github.com/panubo/docker-sshd/blob/main/entry.sh
https://github.com/binlab/docker-bastion/blob/master/bastion
https://github.com/fphammerle/docker-ssh-bastion/blob/master/entrypoint.sh

https://infosec.mozilla.org/guidelines/openssh
https://www.ssh-audit.com/hardening_guides.html#ubuntu_20_04_lts
https://goteleport.com/blog/ssh-bastion-host/

https://goteleport.com/blog/security-hardening-ssh-bastion-best-practices/
https://news.ycombinator.com/item?id=29924053


https://smallstep.com/blog/diy-ssh-bastion-host/

https://10mi2.wordpress.com/2015/01/14/using-ssh-through-a-bastion-host-transparently/
