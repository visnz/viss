modprobe nfs && modprobe nfsd # 加载内核模块 nfs
apt install -y nfs-common 
echo "/nfs        *(rw,fsid=0,sync,no_root_squash)">exports.conf
cat << EOF > ./nfsd.yml
version: '3'
services:
  nfsd:
    image: erichough/nfs-server
    container_name: nfsserver
    volumes:
      - ./exports.conf:/etc/exports:ro
      - /nfs:/nfs
    ports:
      - "2049:2049"
    privileged: true
    restart: always
EOF

mkdir /nfs ; docker-compose -f ./nfsd.yml up -d