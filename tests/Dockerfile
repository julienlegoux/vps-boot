FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git gnupg iproute2 openssh-server sudo \
    systemd systemd-sysv dbus ufw procps psmisc shellcheck python3 \
    python3-yaml util-linux && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd
WORKDIR /workspace
CMD ["bash", "tests/test_vps_boot.sh"]
