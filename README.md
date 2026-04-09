# Dragonfly Docker Development Environment

A ready-to-use Docker container for building and developing [Dragonfly](https://github.com/dragonflydb/dragonfly) — an in-memory data store compatible with Redis and Memcached APIs that delivers up to 25x more throughput than Redis.

## What you get

After setup, you will have a Docker container with:

- **Full C++ toolchain** — Clang 18, CMake, Ninja, Mold linker, ccache
- **All Dragonfly dependencies** pre-installed (Boost, libevent, libssl, RE2, etc.)
- **Debugging and profiling** — GDB, Valgrind, AFL++ fuzzer
- **Benchmarking** — memtier-benchmark, redis-cli
- **Modern shell** — Zsh with Oh-My-Zsh, syntax highlighting, autosuggestions, vi-mode
- **Modern CLI tools** — ripgrep, fd, eza, bat, jq, htop
- **Additional languages** — Python 3.10, Node.js LTS, Go 1.24, Rust
- **Docker-in-Docker** support
- **Neovim** as default editor

Your Dragonfly source code is mounted from the host, so you can edit with your preferred IDE and build inside the container.

## Prerequisites

- Docker
- Git
- ~5 GB disk space for the container image

## Quick start

### 1. Clone Dragonfly

```sh
cd ~
git clone --recursive https://github.com/dragonflydb/dragonfly
```

> **Important:** Use `--recursive` to fetch all submodules.

### 2. Clone this repository

```sh
cd ~
git clone https://github.com/vyavdoshenko/dragonfly-docker-dev
cd dragonfly-docker-dev
```

### 3. Build the container image

```sh
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t builder .
```

The `UID`/`GID` arguments ensure file permissions inside the container match your host user — files you create won't end up owned by root.

### 4. Add shell helper functions

Add the following functions to your `~/.zshrc` (or `~/.bashrc`). These are taken from [vyavdoshenko/orgmode/zshrc.org](https://github.com/vyavdoshenko/orgmode/blob/main/zshrc.org) and provide convenient container management:

```sh
build() {
  if [ -z "$1" ]; then
    echo "Error: You must specify the image tag!"
    echo "Usage example: build my_project"
    return 1
  fi
  docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t "$1" .
}

run() {
  if [ -z "$1" ]; then
    echo "Error: You must specify the image name!"
    echo "Usage example: run builder [container_name] [additional_docker_params]"
    return 1
  fi

  local image_name="$1"
  local container_name="${2:-${image_name}-container}"
  local project_dir="${HOME}/${image_name}"
  shift
  if [ $# -gt 0 ]; then shift; fi

  # Reattach if the container already exists
  if [ "$(docker ps -a -q -f name=${container_name})" ]; then
    docker start -ai "${container_name}"
    return 0
  fi

  docker run --user builder "$@" \
    --mount type=bind,source="${project_dir}",destination="/home/builder/${image_name}" \
    --mount type=bind,source="${HOME}/.ssh",destination="/home/builder/.ssh",readonly \
    --mount type=bind,source="${HOME}/.gitconfig",destination="/home/builder/.gitconfig",readonly \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --privileged \
    -it --name "${container_name}" "${image_name}" /usr/bin/zsh
}

restart() {
  if [ -z "$1" ]; then
    echo "Error: You must specify the image name!"
    echo "Usage example: restart builder [container_name]"
    return 1
  fi

  local image_name="$1"
  local container_name="${2:-${image_name}-container}"

  if [ "$(docker ps -a -q -f name=${container_name})" ]; then
    docker rm -f "${container_name}"
  fi

  run "$@"
}

attach() {
  if [ -z "$1" ]; then
    echo "Error: You must specify the image name!"
    echo "Usage example: attach builder"
    return 1
  fi
  docker exec -it "${1}-container" /usr/bin/zsh
}
```

Then reload your shell:

```sh
source ~/.zshrc
```

### 5. Start the container

```sh
run dragonfly
```

This will:
- Mount `~/dragonfly/` (the Dragonfly source) into the container at `/home/builder/dragonfly`
- Mount your SSH keys (read-only) and gitconfig for Git operations
- Forward the Docker socket for Docker-in-Docker
- Drop you into a Zsh shell inside the container

> **Note:** The `run` function names the container `dragonfly-container`. If you stop and `run dragonfly` again, it reattaches to the existing container — your state is preserved.

To start a fresh container (discarding container state):

```sh
restart dragonfly
```

To open a second shell in a running container:

```sh
attach dragonfly
```

## Building Dragonfly inside the container

Once inside the container:

```sh
cd ~/dragonfly

# Configure (release build)
./helio/blaze.sh -release

# Build
cd build-opt
ninja dragonfly
```

Run the server:

```sh
./dragonfly --alsologtostderr
```

Dragonfly responds to both Redis and HTTP on port `6379`. Test it:

```sh
redis-cli ping
# PONG
```

### Debug build

```sh
cd ~/dragonfly
./helio/blaze.sh    # without -release
cd build-dbg
ninja dragonfly
```

### Useful build flags

For a minimal build (faster compilation):

```sh
./helio/blaze.sh -DUSE_MOLD:BOOL=ON -DWITH_AWS:BOOL=OFF -DWITH_GCP:BOOL=OFF
```

## Log colorization

The container includes a `colorize` utility that highlights Dragonfly log output. Pipe build or runtime output through it:

```sh
./dragonfly --alsologtostderr 2>&1 | colorize
```

- Lines starting with `I` (info) are highlighted in green
- Lines starting with `W` (warning) in yellow
- Lines starting with `E` (error) in red

Use `colorize cut` for a compact view that strips timestamps:

```sh
./dragonfly --alsologtostderr 2>&1 | colorize cut
```

## Benchmarking

The container includes [memtier-benchmark](https://github.com/RedisLabs/memtier_benchmark) for performance testing:

```sh
# Start Dragonfly first, then in another shell:
memtier_benchmark --threads=4 --test-time=30
```

## Multi-architecture build (ARM64)

To build the container for ARM64 (e.g., Apple Silicon host targeting ARM):

```sh
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker build --platform linux/arm64 --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t builder .
```

## What's inside

| Category | Tools |
|---|---|
| **C++ Toolchain** | Clang 18, GCC/G++, CMake, Ninja, Mold, ccache, LLD 18 |
| **Debugging** | GDB, Valgrind, AFL++ 4.34c (with persistent record) |
| **Libraries** | Boost, libevent, libssl, zlib, libunwind, RE2, libxml2, libzstd |
| **Benchmarking** | memtier-benchmark, redis-cli |
| **Languages** | Python 3.10 (venv), Node.js LTS, Go 1.24.1, Rust |
| **Editors** | Neovim, Vim |
| **Shell** | Zsh, Oh-My-Zsh, syntax highlighting, autosuggestions, vi-mode |
| **CLI Tools** | ripgrep, fd, eza, bat, jq, htop, tmux, mc |
| **Containers** | Docker CE, docker-compose, buildx |
| **Network** | iproute2, netcat, telnet, ping, net-tools |
| **VCS** | Git, GitHub CLI (gh) |

## License

MIT
