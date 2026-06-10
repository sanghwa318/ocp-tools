#!/bin/bash
#################### localrepo ########################
function localrepo {
ls /etc/yum.repos.d/bk > /dev/null 2>&1
REPO_BK=$?

if [ ${REPO_BK} != 0 ]; then
	 mkdir -p /etc/yum.repos.d/bk
	  mv /etc/yum.repos.d/*repo /etc/yum.repos.d/bk
fi



ls /etc/yum.repos.d/local.repo > /dev/null 2>&1
REPO=$?

if [ ${REPO} != 0 ]; then
	/bin/cat << EOF >> /etc/yum.repos.d/local.repo
[AppStream-iso]
name=AppStream-iso
baseurl=file:///media/AppStream
gpgcheck=0
enabled=1

[BaseOS-iso]
name=BaseOS-iso
baseurl=file:///media/BaseOS
gpgcheck=0
enabled=1
EOF
else
	echo
	echo "Localrepo already configured" 
fi
}
#########################################################


####################### iso mount #######################
function iso_mount {
lsblk /dev/sr0 > /dev/null 2>&1 

if [ $? -ne 0 ]; then
	echo
	echo "ISO image is not mounted. Check your device or vm setting."
	echo ""
        exit 1
fi

cat /etc/fstab |grep sr0 > /dev/null 2>&1

MOUNT=$?

if [ ${MOUNT}  	-eq 1 ]; then
	echo "/dev/sr0 /media iso9660 defaults 0 0" >> /etc/fstab
	echo
	cat /etc/fstab
	echo
	echo
elif [ ${MOUNT} -eq 0 ]; then
	echo ""
	cat /etc/fstab |grep sr0
	echo ""
	echo "/dev/sr0 already exists in /dec/fstab"
	echo ""
fi

echo
mount -a
}
########################################################

##################### install pkg ######################
function install_pkg {
mount | grep media > /dev/null 2>&1
#if [ $? -eq  0 ]; then
	 yum repolist
	  
	   pkglist="sysstat syslinux net-tools bind-utils bind vim sos tar gzip zip unzip chrony nfs-utils httpd haproxy rsyslog jq podman tftp-server dhcp-server bash-completion wget keepalived"
	     yum install -y ${pkglist}

#     else
#	     echo
#	     echo "There is no iso image mounted"
#	     exit 1
#fi
}
#########################################################




##################### Arrange Daemon #####################
function daemon_arrange {
for stop in $(chkconfig --list | awk '{print $1}' | cut -d : -f 1)
do
	chkconfig $stop off
done

chkconfig network on

for stop in $(systemctl list-unit-files --type service| awk '{print $1}' | cut -d : -f 1)
do
	systemctl disable $stop
done

DAEMON="acpid arptables auditd crond gpm irqbalance kdump lm_sensors messagebus microcode chronyd rpcbind rsyslog sysstat sshd gdm NetworkManager getty@tty1 dbus-broker"

for start in $DAEMON.service
do
	systemctl enable $start
done
}
##########################################################

############### firewalld, selinux disable ###############
function disable_selinux {
grep ^SELINUX=disabled /etc/selinux/config > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "SELINUX is already disabled."
else
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
grubby --update-kernel ALL --args selinux=0
echo
echo " Selinux config changed. Need to reboot system "
echo
fi
}

function disable_fw {
systemctl is-enabled firewalld > /dev/null 2>&1
if [ $? -eq 0 ]; then
systemctl disable --now firewalld
else 
	echo ""
	echo "firewalld is already disabled."
	echo ""
fi
systemctl is-enabled firewalld
systemctl is-active firewalld
}
##########################################################


######################## run script ####################
localrepo
iso_mount
install_pkg 
daemon_arrange 
disable_selinux 
disable_fw 
