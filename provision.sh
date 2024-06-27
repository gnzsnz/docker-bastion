#!/usr/bin/env bash
###############################################################################
# provision.sh
#
# sshd bastion
#
# provisioning script for sshd bastion docker image. this script will provision
# the bind mount $PWD/data:/data (host:container)
#
# docker run -it --rm --env-file .env \
#  --hostname=bastion \
#  -v $PWD/data:/data \
#  --name bastion_provision \
#  gnzsnz/bastion:202208 /provision.sh
###############################################################################

set -e

# set container DATA directory variable
DATA=/data
PROVISIONED_HASH=/etc/ssh/bastion_provisioned_hash

TOTP_URI2="&algorithm=SHA1&digits=6&period=30"

# default shell is no login shell
[ -z "$USER_SHELL" ] && USER_SHELL='/usr/sbin/nologin'

#
check_user_vars() {
	# check user vars
	# USERS
	if [ -z "$USERS" ]; then
		echo "$USERS is not set"
	fi
	echo "$USERS"
}

#
check_provision() {
	# verify hash
	if [ ! -f "$DATA/$PROVISIONED_HASH" ]; then
		echo "> Container not provisioned."
	elif sha256sum -c "$DATA/$PROVISIONED_HASH"; then
		echo "> checksum valid. data dir provisioned"
	else
		echo "> checksum FAILED. Don't panic data/ will be provisioned ..."
	fi
}

#
create_data_dir() {
	# check data directory
	if [ ! -d "$DATA" ]; then
		# create data dir
		echo "> Create DATA dir $DATA ..."
		mkdir "$DATA"
	fi

	if [ ! -d "$DATA/etc" ]; then
		# create data/etc dir
		echo "> Create DATA dir $DATA/etc ..."
		mkdir "$DATA/etc"
	fi

	if [ ! -d "$DATA/etc/ssh" ]; then
		# create data/etc/ssh dir
		echo "> Create DATA dir $DATA/etc/ssh ..."
		mkdir "$DATA/etc/ssh"
	fi

	if [ ! -d "$DATA/home" ]; then
		# create data/home dir
		echo "> Create DATA dir $DATA/home ..."
		mkdir "$DATA/home"
	fi

	if [ ! -L /home ]; then
		# link home directory
		mv /home /home-dist
		ln -sf "$DATA/home" /
	fi
}

create_users() {

	if [ -f "$DATA/$PROVISIONED_HASH" ]; then
		# use files from DATA (there is something there)
		cp -pv "$DATA/etc/passwd" "$DATA/etc/shadow" "$DATA/etc/group" /etc
	fi

	# create users from USERS var
	IFS=','
	for _user in $USERS; do
		if ! id "$_user"; then
			adduser --disabled-password \
				--shell "$USER_SHELL" \
				--quiet \
				--gecos "$_user" "$_user"
			usermod -a -G ssh-bastion "$_user"
		fi
		# TOTP provision
		_totp_ga="/home/$_user/.google_authenticator"
		if [ "$TOTP_ENABLED" == "yes" ] && [ ! -f "$_totp_ga" ]; then
			echo "> TOTP enabled, creating user secret for $_user ..."
			_totp_uri="/home/$_user/totp_uri"
			_totp_qr="/home/$_user/totp_qr"
			# generate secret
			google-authenticator -q -C -t -d -f -r 3 -R 30 -w 3 -s "$_totp_ga"
			chown "$_user:$_user" "$_totp_ga"
			# generate totp uri
			SECRET=$(head -n1 "$_totp_ga")

			[ -z "$TOTP_ISSUER" ] && TOTP_ISSUER='Bastion'

			TOTP_URI="otpauth://totp/$TOTP_ISSUER:$_user@bastion?secret=$SECRET&issuer=$TOTP_ISSUER"
			TOTP_URI+=$TOTP_URI2
			echo "$TOTP_URI" >"$_totp_uri"
			chown "$_user:$_user" "$_totp_uri"
			chmod 400 "$_totp_uri"

			[ -z "$TOTP_QR_ENCODE" ] && TOTP_QR_ENCODE='UTF8'
			# generate qr code
			qrencode -o "$_totp_qr" -t "$TOTP_QR_ENCODE" <"$_totp_uri"
			chown "$_user:$_user" "$_totp_qr"
			chmod 400 "$_totp_qr"
		fi

	done

	# move updated files to DATA
	cp -pv /etc/passwd /etc/shadow /etc/group "$DATA"/etc
}

set_keys_permissions() {
	#
	for _u in "$DATA"/home/*; do
		_user=$(echo "$_u" | cut - -d / -f 4)
		echo "> Setting user permission: $_user "
		if id "$_user"; then
			if [ -d "$DATA/home/$_user" ]; then
				chown -R "$_user:$_user" "$DATA/home/$_user"
				chmod 750 "$DATA/home/$_user"
				[ -d "$DATA/home/$_user/.ssh" ] &&
					chmod 750 "$DATA/home/$_user/.ssh"
			else
				echo "> No home directory for user: $_user"
			fi
			if [ -f "$DATA/home/$_user/.ssh/authorized_keys" ]; then
				chmod 640 "$DATA/home/$_user/.ssh/authorized_keys"
				echo "> authorized_keys permissions set for $_user"
			else
				echo "> No authorized_keys for $_user"
			fi
		else
			echo "> User: $_u does not exists."
		fi
	done
}

set_sshd_config() {
	# if sshd config has been already provisioned use existing files
	if [ -f "$DATA/etc/ssh/sshd_config" ]; then
		if [ -d /etc/ssh ]; then
			mv /etc/ssh /etc/ssh-dist
		fi
		# create link so sha256sum works with /etc/ssh/* files.
		# this is required for container runtime sha256sum validation
		ln -sf ${DATA}/etc/ssh /etc/
	else
		# not provisioned, use container sshd config
		cp -pvr /etc/ssh ${DATA}/etc/
		mv /etc/ssh /etc/ssh-dist
		# create link so sha256sum works with /etc/ssh/* files.
		# this is required for container runtime sha256sum validation
		ln -sf ${DATA}/etc/ssh /etc/
	fi

	if ! ls /etc/ssh/ssh_host_*key*; then
		# Dockerfile will delete host keys, create new keys if needed
		# create host keys
		echo "> Creating host keys ..."
		ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
		ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
	fi

	echo "> Setting /etc/ssh/* permissions and ownership"
	chown root:root "$DATA"/etc/ssh/
	# set 644 onwership, 600 for private key
	find "$DATA"/etc/ssh/ -type f -exec chmod 644 {} \;
	chmod 600 "$DATA"/etc/ssh/ssh_host*key
}

set_checksum() {
	# hash provisioned files, using /etc as root directory
	# that's how the run container will see it
	echo "> Hashing files: "
	sha256sum /etc/passwd /etc/group \
		/etc/shadow /etc/ssh/sshd_config \
		/etc/ssh/ssh_host_*_key* >"$PROVISIONED_HASH"

	# include host certificate
	if [ -f "$SSHD_HOST_CERT" ]; then
		sha256sum "$SSHD_HOST_CERT" >>"$PROVISIONED_HASH"
	elif [ -f '/etc/ssh/ssh_host_ed25519_key-cert.pub' ]; then
		sha256sum /etc/ssh/ssh_host_ed25519_key-cert.pub >>"$PROVISIONED_HASH"
	fi
	# include user CA
	if [ -f "$SSHD_USER_CA" ]; then
		sha256sum "$SSHD_USER_CA" >>"$PROVISIONED_HASH"
	elif [ -f '/etc/ssh/user_ca.pub' ]; then
		sha256sum /etc/ssh/user_ca.pub >>"$PROVISIONED_HASH"
	fi

	# checksum the full file
	sha256sum "$PROVISIONED_HASH" >"${PROVISIONED_HASH}.sum"

	cat "$PROVISIONED_HASH" "${PROVISIONED_HASH}.sum"
}

#
echo "> Starting SSH Bastion 🏯 provisioning ... "

echo "> Data dir: $DATA"
#check_provision
create_data_dir
check_user_vars
create_users
echo "> Users created: $USERS"
set_keys_permissions
echo "> Autorized keys set"
set_sshd_config
echo "> sshd config set"

echo "> Host key 🔑 fingerprints"
ssh-keygen -lf $DATA/etc/ssh/ssh_host_rsa_key
ssh-keygen -lf $DATA/etc/ssh/ssh_host_ed25519_key

set_checksum
echo "> Checksum set 🔑"

echo "> SSH Bastion 🏯 provisioning completed ... "
