#!/bin/bash

# Update YUM repo
yum check-update -y

# Install required applications
sudo yum install -y git zip unzip wget awscli git
sudo yum install docker.io -y
sudo yum install -y java-1.8.0-openjdk.x86_64
sudo /usr/sbin/alternatives --set java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java
sudo /usr/sbin/alternatives --set javac /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/javac
sudo yum remove java-1.7
wget https://releases.hashicorp.com/terraform/0.9.8/terraform_0.9.8_linux_amd64.zip
sudo unzip terraform_0.9.8_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install NFS client required packages
echo "Installing NFS client required packages"
yum -y install nfs-utils bind-utils

# Create EFS mount mount point
echo "Creating the EFS mount point"
cd /; mkdir ${efs_mountpoint}

# Wait for EFS DNS to propagate
echo "Checking to see if EFS DNS is ready"
nslookup ${efs_filesystem_id}.efs.${aws_region}.amazonaws.com 
while [ $? -ne 0 ] 
do 
  sleep 30 
  echo "Waiting for EFS dns to propagate" 
  nslookup ${efs_filesystem_id}.efs.${aws_region}.amazonaws.com 
done

# Check to see if EFS is already mounted
echo "Checking to see if EFS is already mounted"
if grep -qs ${efs_filesystem_id}; then
  echo "NFS mount ${efs_filesystem_id}.efs.${aws_region}.amazonaws.com already exists. No need to mount"
else
  mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${efs_filesystem_id}.efs.${aws_region}.amazonaws.com:/ ${efs_mountpoint}
fi

# Check for correct mount point directory ownership
echo "Setting mount point ownership"
chown ${efs_mountpoint_owner} ${efs_mountpoint} 

# Check if /etc/fstab has been modified
echo "Modifying /etc/fstab, if necessary"
cat /etc/fstab | grep "${efs_filesystem_id}"
if [ $? -eq 0 ]; then
  echo "NFS mount ${efs_filesystem_id}.efs.${aws_region}.amazonaws.com already exists. No need to modify /etc/fstab"
else
  echo "${efs_filesystem_id}.efs.${aws_region}.amazonaws.com:/ ${efs_mountpoint} nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
fi

# Add instance to the ECS cluster
echo "Adding instance to the ECS cluster"
echo "ECS_CLUSTER=${ecs_cluster_name}" >> /etc/ecs/ecs.config

# Restart ECS and Docker
echo "Restarting ECS and Docker"
sudo stop ecs
sudo service docker restart
sudo start ecs
