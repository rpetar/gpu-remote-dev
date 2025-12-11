# GPU Remote Dev Container

A minimal GPU-ready dev container for remote coding. It supports two connection modes:

- **SSH**: publish an SSH port and connect with your own public key.
- **VS Code Tunnel**: host a VS Code dev tunnel and connect via the Remote Explorer.

The container also detects GPUs, primes CUDA cache, and can clone a GitHub repo on startup.

## Prerequisites
- Docker (or a provider like Vast.ai that can run a Docker image).
- Host with an NVIDIA GPU and drivers; container started with `--gpus all` and NVIDIA Container Toolkit available.
- For tunnel mode: VS Code CLI already in the image (included) and a valid dev tunnel host token.
- For SSH mode: an SSH keypair on your local machine (or generate with `ssh-keygen -t ed25519`).

## Environment Variables
Common:
- `CONNECT_MODE`: `ssh`, `tunnel`, or `auto` (default). In `auto`, SSH is used if `PUBLIC_SSH_KEY` is set, otherwise tunnel.

SSH mode:
- `PUBLIC_KEY` or `SSH_PUBLIC_KEY` (required): Your public key line (e.g., output of `cat ~/.ssh/id_ed25519.pub`). Vast.ai can inject your account key into `PUBLIC_KEY`/`SSH_PUBLIC_KEY` automatically.
- `SSH_USER` (optional, default `root`): User account to authorize/create.
- `SSH_PORT` (optional, default `2222`): SSH daemon port inside the container.

Tunnel mode:
- `TUNNEL_ID` (required): Existing dev tunnel ID.
- `ACCESS_TOKEN` (required): Dev tunnel host token (`devtunnel token --scope host --scope manage --tunnel <id>`).
- `TUNNEL_NAME` (optional, default `gpu-workspace`): Display name for the tunnel.

Repository cloning:
- `GITHUB_REPO_URL`: HTTPS URL of the repo to clone.
- `GITHUB_TOKEN`: GitHub token with repo access (used for cloning).
- `PROJECT_DIR` (optional): Target path (default `/workspace/<repo-name>`).
- `CLONE_ON_START` (optional, default `true`): Set to `false` to skip cloning.

Git identity (for committing over SSH):
- `GIT_USER_NAME` and `GIT_USER_EMAIL` (optional): If both are set, the bootstrap script sets `git config --global user.name` and `user.email` automatically. If already configured globally, they are left unchanged.

## Local Testing (SSH)
1. Get your public key: `cat ~/.ssh/id_ed25519.pub`.
2. Build: `docker build -t gpu-remote-dev .`
3. Run with SSH exposed:
   ```
   docker run --rm -it \
     --gpus all \
     -e CONNECT_MODE=ssh \
     -e PUBLIC_KEY="ssh-ed25519 AAAA... your-comment" \
     -e SSH_PORT=2222 \
     -p 2222:2222 \
     gpu-remote-dev
   ```
4. Connect: `ssh -p 2222 root@localhost` (or your `SSH_USER`). For VS Code, add to `~/.ssh/config`:
   ```
   Host gpu-local
     HostName localhost
     Port 2222
     User root
     IdentityFile ~/.ssh/id_ed25519
   ```
   Then use “Remote-SSH: Connect to Host…” → `gpu-local`.

## Local Testing (VS Code Tunnel)
1. Create a tunnel: `devtunnel create --name gpu-dev` (or reuse an existing one).
2. Get a host token: `devtunnel token --scope host --scope manage --tunnel <tunnel-id>`.
3. Run the container:
   ```
   docker run --rm -it \
     --gpus all \
     -e CONNECT_MODE=tunnel \
     -e TUNNEL_ID=<your-id> \
     -e ACCESS_TOKEN=<host-token> \
     gpu-remote-dev
   ```
4. Connect from VS Code: Remote Explorer → Tunnels → select your tunnel ID.

## Using on Vast.ai (SSH recommended)
1. Add your SSH public key to your Vast.ai account (it will be injected into `PUBLIC_KEY`/`SSH_PUBLIC_KEY`). Launch with envs: `CONNECT_MODE=ssh`, optionally `SSH_USER`, `SSH_PORT` (default 2222). You can also explicitly set `PUBLIC_KEY="ssh-ed25519 ..."` if needed.
2. In the template, set the internal TCP port to `SSH_PORT` (default 2222). Vast assigns an external host port automatically.
3. After the instance starts, click the IP in the UI to see the port mappings. Use the external host port mapped to container 2222.
4. Connect from your machine: `ssh -p <external_host_port> <SSH_USER>@<vast_public_ip>`.
5. VS Code Remote-SSH config example:
   ```
   Host vast-gpu
     HostName <vast_public_ip>
     Port <external_host_port>   # the host port mapped to container 2222
     User <SSH_USER>
     IdentityFile ~/.ssh/id_ed25519
   ```

## Notes
- The entrypoint runs `start.sh`, which picks the mode, sets up the connection, runs GPU detection, and clones the repo (if configured).
- Logs: `/tmp/sshd.log` for SSH mode, `/tmp/vscode_tunnel.log` for tunnel mode.
- If you hit devtunnel rate limits or prefer self-managed access, use SSH mode.
