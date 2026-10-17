#!/usr/bin/env bash
# Comandos de ejemplo para EFS. Define FS_ID.
set -euo pipefail
FS_ID="${FS_ID:?define FS_ID (fs-...)}"

aws efs describe-file-systems --file-system-id "$FS_ID" \
  --query 'FileSystems[0].{Estado:LifeCycleState,Cifrado:Encrypted,Throughput:ThroughputMode,Bytes:SizeInBytes}'
aws efs describe-mount-targets --file-system-id "$FS_ID" \
  --query 'MountTargets[].{AZ:AvailabilityZoneName,Subred:SubnetId,IP:IpAddress,Estado:LifeCycleState}'
aws efs describe-access-points --file-system-id "$FS_ID" \
  --query 'AccessPoints[].{Id:AccessPointId,Raiz:RootDirectory.Path,Uid:PosixUser.Uid}'
aws efs describe-lifecycle-configuration --file-system-id "$FS_ID"
aws efs describe-file-system-policy --file-system-id "$FS_ID"

# Montaje en EC2 con TLS e IAM (requiere amazon-efs-utils)
#   sudo mount -t efs -o tls,iam,accesspoint=fsap-0123456789abcdef0 "$FS_ID":/ /mnt/efs

# Comprobar que el puerto NFS responde desde la app
#   nc -zv <ip-del-mount-target> 2049
