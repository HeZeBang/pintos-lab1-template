# syntax=docker/dockerfile:1
FROM syrriinge/pintos-sp24:latest

# Install openssh-server and git
RUN apt-get update \
  && apt-get install -y openssh-server git \
  && rm -rf /var/lib/apt/lists/*

# Change root's home directory to /home/student (persists with volume mounts)
RUN mkdir -p /home/student \
  && usermod -d /home/student root \
  && cp -a /root/. /home/student/ 2>/dev/null || true

# Configure SSH
RUN mkdir -p /var/run/sshd \
  && sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
  && sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
  && sed -i 's/#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
  && (sed -i 's/UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || echo "UsePAM no" >> /etc/ssh/sshd_config) \
  && echo "root:root" | chpasswd

# --- Stage seed files on rootfs (never shadowed by bind mount) ---
RUN git clone --depth 1 https://github.com/cs130-shanghaitech/pintos.git /opt/lab-seed/pintos
COPY README.md /opt/lab-seed/README.md
RUN printf '%s\n' \
    'export PATH=$PATH:/home/student/pintos/src/utils' \
    'export GDBMACROS=/home/student/pintos/src/misc/gdb-macros' \
    > /opt/lab-seed/.bashrc

# --- Seed script: copy seed -> /home/student once per persistent volume ---
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'mkdir -p /home/student' \
    'if [ ! -f /home/student/.seeded ]; then' \
    '    echo "Seeding /home/student from /opt/lab-seed (first boot)..."' \
    '    cp -a /opt/lab-seed/. /home/student/' \
    '    date -u +%%FT%%TZ > /home/student/.seeded' \
    'fi' \
    > /usr/local/bin/seed-home.sh \
  && chmod +x /usr/local/bin/seed-home.sh

# --- Startup: seed first, then sshd ---
RUN printf '#!/bin/bash\nset -e\n/usr/local/bin/seed-home.sh\nif [ ! -f /etc/ssh/ssh_host_rsa_key ]; then\n    ssh-keygen -A\nfi\n/usr/sbin/sshd -t\nexec /usr/sbin/sshd -D -e\n' > /start.sh \
  && chmod +x /start.sh

WORKDIR /home/student

EXPOSE 22

CMD ["/start.sh"]
