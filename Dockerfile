FROM ubuntu:24.04

ARG UID
ARG GID

ENV LOCAL_UID=${UID}
ENV LOCAL_GID=${GID}

ENV DEBIAN_FRONTEND=noninteractive

ENV TZ=Europe/Kyiv

RUN apt-get update --fix-missing

RUN apt-get upgrade -y

RUN apt-get dist-upgrade -y

RUN apt-get install -y locales && localedef -i en_US -f UTF-8 en_US.UTF-8

# Generate Ukrainian locale
RUN localedef -i uk_UA -f UTF-8 uk_UA.UTF-8

ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8

RUN apt -y install \
    autoconf \
    autoconf-archive \
    automake \
    bison \
    bsdmainutils \
    build-essential \
    ca-certificates \
    ccache \
    clang-18 \
    clangd \
    cmake \
    curl \
    gdb \
    gh \
    git \
    graphviz \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    libboost-all-dev \
    libboost-fiber-dev \
    libevent-dev \
    liblzma-dev \
    libre2-dev \
    libssl-dev \
    libtool \
    libunwind-dev \
    libxml2-dev \
    libz-dev \
    libzstd-dev \
    lld-18 \
    llvm-18 \
    llvm-18-dev \
    lsb-release \
    lshw \
    mc \
    mold \
    neovim \
    net-tools \
    netcat-openbsd \
    ninja-build \
    npm \
    pciutils \
    pkg-config \
    redis-tools \
    software-properties-common \
    sudo \
    telnet \
    tmux \
    tzdata\
    unzip \
    valgrind \
    vim \
    wget \
    zlib1g-dev \
    zsh

#RUN apt -y install \
#    gcc-14 \
#    g++-14 \

#RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
#    --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
#    --slave /usr/bin/gcov gcov /usr/bin/gcov-14

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
RUN apt-get install -y nodejs

RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update --fix-missing
RUN apt-get upgrade -y

RUN apt -y install \
    python3.10 \
    python3.10-dev \
    python3.10-tk \
    python3.10-venv \
    python3.10-distutils

# Add memtier_benchmark
RUN curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list && \
    apt-get update --fix-missing && \
    apt-get install -y memtier-benchmark

# Add Docker repository and install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update --fix-missing && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Build AFL++ from source with AFL_PERSISTENT_RECORD support
RUN git clone --depth=1 --branch v4.34c https://github.com/AFLplusplus/AFLplusplus.git /opt/AFLplusplus && \
    cd /opt/AFLplusplus && \
    sed -i 's|// #define AFL_PERSISTENT_RECORD|#define AFL_PERSISTENT_RECORD|' include/config.h && \
    make distrib && \
    make install && \
    cd / && rm -rf /opt/AFLplusplus

# Install Go 1.24.1
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  GOARCH=amd64 ;; \
      aarch64) GOARCH=arm64 ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    wget https://go.dev/dl/go1.24.1.linux-${GOARCH}.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go1.24.1.linux-${GOARCH}.tar.gz && \
    rm go1.24.1.linux-${GOARCH}.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/home/builder/go
ENV PATH=$PATH:$GOPATH/bin

RUN existing_user=$(getent passwd $LOCAL_UID | cut -d: -f1) && \
    if [ -n "$existing_user" ]; then \
        echo "Removing existing user: $existing_user with UID $LOCAL_UID"; \
        deluser --remove-home "$existing_user"; \
    fi && \
    if [ -n "$LOCAL_GID" ]; then \
        if ! getent group $LOCAL_GID > /dev/null; then \
            addgroup --gid $LOCAL_GID g${LOCAL_GID}; \
        fi; \
        adduser --uid $LOCAL_UID --gid $LOCAL_GID --gecos "" --disabled-password --home /home/builder --shell /usr/bin/zsh builder; \
    else \
        adduser --uid $LOCAL_UID --gecos "" --disabled-password --home /home/builder --shell /usr/bin/zsh builder; \
    fi

RUN usermod -aG sudo builder && echo "builder ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/builder

# Add builder to docker group
RUN usermod -aG docker builder

# Configure Docker to run without sudo
RUN mkdir -p /etc/docker && \
    echo '{\n  "live-restore": true,\n  "group": "docker"\n}' > /etc/docker/daemon.json

# Install Rust and Cargo for builder user
USER builder
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . "$HOME/.cargo/env" && \
    cargo install fd-find eza ripgrep bat

RUN python3.10 -m venv /home/builder/.venv && \
    /home/builder/.venv/bin/pip install --upgrade pip setuptools wheel

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
RUN git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

RUN git clone https://github.com/dragonflydb/df-afl.git /home/builder/df-afl

USER root

COPY zshrc /home/builder/.zshrc

COPY colorize_script.py /home/builder/.colorize_script.py

WORKDIR /home/builder
