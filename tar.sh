sudo tar --numeric-owner -czpf debian-rootfs.tar.gz -C /mnt/rootfs \
    --exclude=dev \
    --exclude=proc \
    --exclude=sys \
    --exclude=run \
    --exclude=tmp \
    --exclude=mnt \
    --exclude=media \
    --exclude=lost+found \
    --exclude=var/log \
    --exclude=var/tmp \
    --exclude=var/cache/apt/archives \
    --exclude=var/lib/apt/lists \
    .
