"""Docker bastion build and test tasks."""

import os
from pathlib import Path

import invoke
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519
from invoke import task
from invoke.collection import Collection

# prepare environment variables
os.environ["BASTION_USER"] = os.getenv("BASTION_USER", "bastion")
os.environ["IMAGE_VERSION"] = os.getenv("IMAGE_VERSION", "2506.01")
os.environ["SERVER_OS"] = os.getenv("SERVER_OS", "noble")
os.environ["IMAGE_OS"] = os.getenv("IMAGE_OS", "noble")
os.environ["IMAGE_NAME"] = os.getenv("IMAGE_NAME", "gnzsnz/bastion")
os.environ["SERVER_PORT"] = os.getenv("SERVER_PORT", "2022")
os.environ["SSH_LISTEN_PORT"] = os.getenv("SSH_LISTEN_PORT", "2222")

# Define Docker images and paths
openssh_image = (
    f"gnzsnz/openssh:{os.environ['IMAGE_VERSION']}-{os.environ['SERVER_OS']}"
)
bastion_image = f"{os.environ['IMAGE_NAME']}:{os.environ['IMAGE_VERSION']}-{os.environ['IMAGE_OS']}"
docker_wait = 2
ssh_path = f"/home/{os.environ['BASTION_USER']}/.ssh"


def generate_keys():
    """Generate Ed25519 SSH keys for the bastion host."""
    # Generate Ed25519 private key
    host_private_key = ed25519.Ed25519PrivateKey.generate()

    # Get the public key
    host_public_key = host_private_key.public_key()

    # Serialize private key to PEM format
    host_private_pem = host_private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.OpenSSH,
        encryption_algorithm=serialization.NoEncryption(),
    )

    # Serialize public key to OpenSSH format
    host_public_pem = host_public_key.public_bytes(
        encoding=serialization.Encoding.OpenSSH,
        format=serialization.PublicFormat.OpenSSH,
    )
    return host_private_pem, host_public_pem


def write_keys_to_file():
    """Write the generated keys to files."""
    private_key, public_key = generate_keys()  # generate the keys
    # set keys paths and permissions
    private_key_path = Path("./tmp/ssh_host_ed25519_key")
    public_key_path = Path("./tmp/ssh_host_ed25519_key.pub")
    private_key_path.touch(mode=0o600)
    public_key_path.touch(mode=0o644)
    # Write the keys to the files
    private_key_path.write_bytes(private_key)
    public_key_path.write_bytes(public_key)


def run_tasks(tasks):
    """Run a list of shell commands using invoke."""
    for t in tasks:
        result = invoke.run(t, pty=True)
        if result.failed:
            raise invoke.exceptions.UnexpectedExit(
                f"Command failed: {t}\n{result.stderr}"
            )


def generate_tmp_directory():
    """Generate the temporary directory for storing keys."""
    if not os.path.exists("./tmp"):
        os.makedirs("./tmp")
        print("Temporary directory created at ./tmp")

@task
def clean_tmp(context):
    """Clean the temporary directory."""
    tasks = [
        "[ ! -d ./tmp ] && mkdir -vp ./tmp || true",
        "[ -d ./tmp ] && sudo rm -rf ./tmp",
        "mkdir -vp ./tmp/data",
    ]
    run_tasks(tasks)
    generate_tmp_directory()

    print("Temporary directory cleaned.")


@task(clean_tmp)
def generate_ssh_keys(context):
    """
    Generate SSH keys for the bastion host.
    """
    tasks = [
        f"""echo "[host.docker.internal]:{os.environ["SSH_LISTEN_PORT"]} $(<./tmp/ssh_host_ed25519_key.pub)" >> ./tmp/known_hosts""",
    ]

    write_keys_to_file()
    run_tasks(tasks)
    print("SSH keys generated and written to ./tmp/ssh_host_ed25519_key")


@task(generate_ssh_keys)
def get_keys(context):
    """
    Get the keys for the bastion host.
    """
    tasks = [
        f"""docker run -d --name client --rm \
            -v openssh_vol:{ssh_path} {openssh_image} \
            sleep {docker_wait}""",
        f"docker cp client:{ssh_path}/authorized_keys ./tmp/authorized_keys",
        "docker cp client:/etc/ssh/ssh_host_ed25519_key.pub ./tmp/server_host_key.pub",
        # f"docker exec -it client cp -va /etc/ssh/ssh_host_ed25519_key.pub {ssh_path}/known_hosts",
        # f"docker exec -it client chown --reference={ssh_path}/authorized_keys {ssh_path}/known_hosts",
        f"""echo "[host.docker.internal]:{os.environ["SERVER_PORT"]} $(<./tmp/server_host_key.pub)" >> ./tmp/known_hosts""",
        "docker cp ./tmp/known_hosts client:/etc/ssh/ssh_known_hosts",
        f"docker cp ./tmp/known_hosts client:{ssh_path}/known_hosts",
        f"docker exec -it client chown --reference={ssh_path}/authorized_keys {ssh_path}/known_hosts",
        "docker wait client",
    ]
    print("starting to get keys for bastion host...")
    run_tasks(tasks)
    print("Keys copied to /tmp/authorized_keys, /tmp/ssh_host_ed25519_key.pub")


@task(get_keys)
def provision_bastion(context):
    """
    Provision the bastion host.
    """
    tasks = [
        f"mkdir -vp ./tmp/data{ssh_path}",
        "mkdir -vp ./tmp/data/etc/ssh",
        f"cp -va ./tmp/authorized_keys ./tmp/data{ssh_path}/authorized_keys",
        f"cp -va ./tmp/known_hosts ./tmp/data{ssh_path}/known_hosts",
        "cp -va ./tmp/known_hosts ./tmp/data/etc/ssh/ssh_known_hosts",
        "cp -va ./tmp/ssh_host_ed25519_key ./tmp/data/etc/ssh/ssh_host_ed25519_key",
        "cp -va ./tmp/ssh_host_ed25519_key.pub ./tmp/data/etc/ssh/ssh_host_ed25519_key.pub",
        f"""docker run --rm --env-file ../.env -v ./tmp/data:/data \
            {bastion_image} /provision.sh
            """,
    ]

    run_tasks(tasks)
    print("Bastion host provisioned successfully.")


@task
def run_bastion(context):
    """
    Run the bastion host.
    """
    tasks = [
        f"""docker run -d --env-file ../.env -p {os.environ["SSH_LISTEN_PORT"]}:22 \
            -v $PWD/tmp/data/etc/passwd:/etc/passwd:ro \
            -v $PWD/tmp/data/etc/shadow:/etc/shadow:ro \
            -v $PWD/tmp/data/etc/group:/etc/group:ro \
            -v $PWD/tmp/data/etc/ssh:/etc/ssh:ro \
            -v $PWD/tmp/data/home:/home \
            --add-host host.docker.internal:host-gateway \
            --name bastion \
            {bastion_image}
        """
    ]

    run_tasks(tasks)
    print("Bastion host is running.")


@task
def run_server(context):
    """
    Run the OpenSSH server.
    """
    tasks = [
        f"""docker run -d --name server -p {os.environ["SERVER_PORT"]}:22 \
          -v openssh_vol:{ssh_path} \
          {openssh_image} /usr/sbin/sshd -D -e -o LogLevel=VERBOSE""",
    ]

    run_tasks(tasks)
    print("OpenSSH server is running.")


@task(run_bastion, run_server)
def run_docker(context):
    """
    Run both the bastion and OpenSSH server.
    """
    print("Running Docker containers for bastion and OpenSSH server...")


@task
def test_running_ssh(context):
    """
    Test if the SSH server is running and accessible.
    """
    tasks = [
        f"""timeout 1 bash -c '</dev/tcp/0.0.0.0/{os.environ["SSH_LISTEN_PORT"]} && echo "SSH Bastion running" || echo "Bastion Port is closed"' || echo "Bastion Connection timeout"
        """,
        f"""timeout 1 bash -c '</dev/tcp/0.0.0.0/{os.environ["SERVER_PORT"]} && echo "SSH Server running" || echo "SSH Port is closed"' || echo "SSH Connection timeout"
        """,
    ]
    print("Testing SSH connection to bastion host...")
    run_tasks(tasks)
    print("SSH connection test successful.")


@task
def test_server_connection(context):
    """
    Test if the SSH server is accessible from the bastion host.
    """
    tasks = [
        f"""docker run --rm --name client -u bastion \
          --add-host host.docker.internal:host-gateway \
          -v openssh_vol:{ssh_path} {openssh_image} \
          ssh -v -p {os.environ["SERVER_PORT"]} \
          -i {ssh_path}/id_ed25519 \
          {os.environ["BASTION_USER"]}@host.docker.internal ssh -V \
          || (docker logs -t server && exit 1)
        """,
    ]
    print("Testing SSH connection to server...")
    run_tasks(tasks)
    print("SSH connection test to server successful.")


@task
def test_bastion_connection(context):
    """
    Test if the bastion host is accessible from the local machine.
    """
    tasks = [
        f"""docker run --rm --name client -u bastion \
          --add-host host.docker.internal:host-gateway \
          -v openssh_vol:{ssh_path} {openssh_image} \
          ssh -v -p {os.environ["SERVER_PORT"]} \
          -J {os.environ["BASTION_USER"]}@host.docker.internal:{os.environ["SSH_LISTEN_PORT"]} \
          -i {ssh_path}/id_ed25519 \
          {os.environ["BASTION_USER"]}@host.docker.internal ssh -V \
          || (docker logs -t bastion && exit 1)
        """,
    ]
    print("Testing SSH connection to bastion host...")
    run_tasks(tasks)
    print("SSH connection test to bastion host successful.")


@task
def test_bastion_scp(context):
    """
    Test SCP from the bastion host to the server.
    """
    tasks = [
        f"""docker run --rm --name client -u bastion \
          --add-host host.docker.internal:host-gateway \
          -v openssh_vol:{ssh_path} {openssh_image} \
          scp -v -P {os.environ["SERVER_PORT"]} \
          -J {os.environ["BASTION_USER"]}@host.docker.internal:{os.environ["SSH_LISTEN_PORT"]} \
          -i {ssh_path}/id_ed25519 \
          /etc/ssh/ssh_host_ed25519_key.pub {os.environ["BASTION_USER"]}@host.docker.internal:/tmp/server_host_key.pub \
          || (docker logs -t bastion && exit 1)
        """,
        f"""docker run --rm --add-host host.docker.internal:host-gateway \
          --name client -u bastion \
          -v openssh_vol:{ssh_path} {openssh_image} \
          ssh -v -p {os.environ["SERVER_PORT"]} \
          -J {os.environ["BASTION_USER"]}@host.docker.internal:{os.environ["SSH_LISTEN_PORT"]} \
          -i {ssh_path}/id_ed25519 \
          {os.environ["BASTION_USER"]}@host.docker.internal cat /tmp/server_host_key.pub \
          || (docker logs -t bastion && exit 1)
        """,  # verify file transfer
    ]
    print("Testing SCP from bastion host to server...")
    run_tasks(tasks)
    print("SCP test successful.")


@task(
    test_running_ssh, test_server_connection, test_bastion_connection, test_bastion_scp
)
def run_tests(context):
    """
    Run all tests to ensure the setup is working correctly.
    """
    print("All tests completed successfully.")


@task
def stop_docker(context):
    """
    Stop all running Docker containers.
    """
    tasks = [
        "docker stop bastion server || true",
        "docker rm bastion server || true",
        "docker volume rm openssh_vol || true",
    ]
    run_tasks(tasks)
    print("All Docker containers stopped and removed.")


@task(pre=[provision_bastion, run_docker, run_tests], post=[stop_docker,clean_tmp])
def run_all(context):
    """
    Run all tasks in sequence.
    """
    print("All tasks completed successfully.")


ns = Collection()
ns.add_task(clean_tmp, "clean-tmp")
ns.add_task(provision_bastion, "provision-bastion")
ns.add_task(stop_docker, "stop-docker")
ns.add_task(run_all, "run-all")
#ns.configure({'tasks': {'dedup': False}})  # Disable task deduplication
