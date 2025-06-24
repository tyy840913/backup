cd /
tar --exclude=/mnt --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp \
    --exclude=/var/tmp --exclude=/media --exclude=/run --exclude=/boot \
    --exclude=/lost+found --exclude=/swapfile --exclude=/etc/hostname \
    -czpf /root/debian-rootfs.tar.gz .
