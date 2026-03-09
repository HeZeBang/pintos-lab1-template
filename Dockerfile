FROM syrriinge/pintos-sp24:latest

ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create user with sudo, add openssh-server
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo openssh-server \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && chsh -s /bin/bash $USERNAME \
    && echo "$USERNAME:ubuntu" | chpasswd \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && (sed -i 's/UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || echo "UsePAM no" >> /etc/ssh/sshd_config)

# Set up PintOS environment for ubuntu user
RUN echo 'export PATH=$PATH:/root/pintos/src/utils' >> /home/$USERNAME/.bashrc \
    && echo 'export GDBMACROS=/root/pintos/src/misc/gdb-macros' >> /home/$USERNAME/.bashrc \
    && chown -R $USERNAME:$USERNAME /home/$USERNAME

# Copy welcome message
COPY README.md /home/ubuntu/README.md
RUN chown ubuntu:ubuntu /home/ubuntu/README.md

# Create startup script (runs as root to start sshd)
RUN printf '#!/bin/bash\nset -e\nif [ ! -f /etc/ssh/ssh_host_rsa_key ]; then\n    ssh-keygen -A\nfi\n/usr/sbin/sshd -t\nexec /usr/sbin/sshd -D -e\n' > /start.sh \
    && chmod +x /start.sh

WORKDIR /home/ubuntu

EXPOSE 22

# Run as root so sshd can bind port 22
CMD ["/start.sh"]
