ARG BASE_IMAGE=ubuntu:22.04
ARG BASE_RUNTIME_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu20.04

FROM ${BASE_IMAGE} AS build-python-stage

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ARG PIP_NO_CACHE_DIR=1
ARG PYENV_VERSION=v2.6.1
ARG PYTHON_VERSION=3.10.18

RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        curl \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        git

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

RUN <<EOF
    set -eu

    git clone https://github.com/pyenv/pyenv.git /opt/pyenv
    cd /opt/pyenv
    git checkout "${PYENV_VERSION}"

    PREFIX=/opt/python-build /opt/pyenv/plugins/python-build/install.sh
    /opt/python-build/bin/python-build -v "${PYTHON_VERSION}" /opt/python

    rm -rf /opt/python-build /opt/pyenv
EOF

FROM ${BASE_RUNTIME_IMAGE} AS build-python-venv-stage

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN <<EOF
    set -eu

    apt-get update
    apt-get install -y \
        git \
        gosu

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

ARG VENV_BUILDER_UID=999
ARG VENV_BUILDER_GID=999
RUN <<EOF
    set -eu

    groupadd --non-unique --gid "${VENV_BUILDER_GID}" venvbuilder
    useradd --non-unique --uid "${VENV_BUILDER_UID}" --gid "${VENV_BUILDER_GID}" --create-home venvbuilder
EOF

COPY --from=build-python-stage --chown=root:root /opt/python /opt/python
ENV PATH="/opt/python/bin:${PATH}"

RUN <<EOF
    set -eu

    mkdir -p /opt/python_venv
    chown -R "${VENV_BUILDER_UID}:${VENV_BUILDER_GID}" /opt/python_venv

    gosu venvbuilder python -m venv /opt/python_venv
EOF
ENV PATH="/opt/python_venv/bin:${PATH}"

COPY --chown=root:root ./requirements.txt /python_venv_tmp/
RUN --mount=type=cache,uid=${VENV_BUILDER_UID},gid=${VENV_BUILDER_GID},target=/home/venvbuilder/.cache/pip <<EOF
    set -eu

    gosu venvbuilder pip install -r /python_venv_tmp/requirements.txt
EOF