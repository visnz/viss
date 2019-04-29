# modify $NFS_IP to your nfs server ip address
apt install -y nfs-common && mkdir /nfs && mount -o nfsvers=4 $NFS_IP:/  /nfs