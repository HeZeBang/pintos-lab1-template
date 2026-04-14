FROM syrriinge/pintos-sp24:latest

# Install openssh-server and git
RUN apt-get update \
  && apt-get install -y openssh-server git \
  && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir -p /var/run/sshd \
  && sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
  && sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
  && sed -i 's/#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
  && (sed -i 's/UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || echo "UsePAM no" >> /etc/ssh/sshd_config) \
  && echo "root:root" | chpasswd

# Set up PintOS environment for root
RUN echo 'export PATH=$PATH:/root/pintos/src/utils' >> /root/.bashrc \
  && echo 'export GDBMACROS=/root/pintos/src/misc/gdb-macros' >> /root/.bashrc

# Clone pintos repo
RUN git clone https://github.com/cs130-shanghaitech/pintos.git /root/pintos

# Copy welcome message
COPY README.md /root/README.md

# Create startup script
RUN printf '#!/bin/bash\nset -e\nif [ ! -f /etc/ssh/ssh_host_rsa_key ]; then\n    ssh-keygen -A\nfi\n/usr/sbin/sshd -t\nexec /usr/sbin/sshd -D -e\n' > /start.sh \
  && chmod +x /start.sh

WORKDIR /root

EXPOSE 22

CMD ["/start.sh"]
