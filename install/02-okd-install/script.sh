#!/bin/bash
HOST='bastion'
CLUSTER='lgu'
DOMAIN='okd'
export HOST=$HOST
export CLUSTER=$CLUSTER
export DOMAIN=$DOMAIN



export PXENET=192.168.12
export PXEBASTION=192.168.12.11

export BASTIONNET="192.168.11"
export BASTIONIP=${BASTIONNET:=$PXENET}.10

export BASTIONRIP1=192.168.11.11
export BASTIONRIP2=192.168.11.12

#################### hosts ############################
function etchosts {
/bin/cat << EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

## OKD CLUSTER ##
EOF

cat hosts.txt | awk '{print$3" "$1}' >> /etc/hosts
}
#######################################################

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

###############
function dns_install {
DO=$DOMAIN
CL=$CLUSTER
DO1=$(echo $DO | awk -F '.' '{print $1}')

/bin/cat << EOF > /etc/named/${CL}.${DO1}.zones 
zone "${CL}.${DO}" IN { 
  type master;
    file "/var/named/${CL}.${DO}.zone";
  allow-update { none; };
};
EOF

/bin/cat << EOF > /etc/named.conf
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//

options {
	listen-on port 53 { any; };
	listen-on-v6 port 53 { none; };
	directory 	"/var/named";
	dump-file 	"/var/named/data/cache_dump.db";
	statistics-file "/var/named/data/named_stats.txt";
	memstatistics-file "/var/named/data/named_mem_stats.txt";
	secroots-file	"/var/named/data/named.secroots";
	recursing-file	"/var/named/data/named.recursing";
	allow-query     { any; };

	/* 
	 - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
	 - If you are building a RECURSIVE (caching) DNS server, you need to enable 
	   recursion. 
	 - If your recursive DNS server has a public IP address, you MUST enable access 
	   control to limit queries to your legitimate users. Failing to do so will
	   cause your server to become part of large scale DNS amplification 
	   attacks. Implementing BCP38 within your network would greatly
	   reduce such attack surface 
	*/
	recursion yes;

	dnssec-validation no;

	managed-keys-directory "/var/named/dynamic";
    geoip-directory "/usr/share/GeoIP";

	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";

	/* https://fedoraproject.org/wiki/Changes/CryptoPolicy */
	include "/etc/crypto-policies/back-ends/bind.config";
};
logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
	type hint;
	file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
include "/etc/named/${CL}.${DO1}.zones";
EOF

/bin/cat << EOF > /var/named/${CL}.${DO}.zone 
\$TTL 1D
@   IN SOA  @ ns.${CL}.${DO}. (
      20220331 ; serial
      3H     ; refresh
      1H     ; retry
      1W     ; expiry
      1H )    ; minimum
@           IN NS       ns.${CL}.${DO}.
@      IN A    ${BASTIONIP}
ns   IN A    ${BASTIONIP}
;
api      IN A      ${BASTIONIP} ; external LB interface
api-int   IN A      ${BASTIONIP} ; internal LB interface
apps    IN A      ${BASTIONIP}
*.apps   IN A      ${BASTIONIP}
;
bastion       IN A        ${BASTIONIP}
bastion1      IN A        ${BASTIONRIP1}
bastion2      IN A        ${BASTIONRIP2}
; okd Cluster
EOF
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    read -ra col <<< "$line"
    NODENAME=${col[0]}
    NODEROLE=${col[1]}
    NODEIP=${col[2]}
    NODEGW=${col[3]}
    NODEMAC=${col[4]}
    SLAVE=${col[5]}

/bin/cat << EOF >> /var/named/${CL}.${DO}.zone
${NODENAME}.      IN A        ${NODEIP}
EOF
done < hosts.txt

echo
systemctl enable --now named
systemctl status named --no-pager
echo
nslookup ${CL}.${DO}
}
##################################################################
function haproxy_install {
/bin/cat << EOF > /etc/haproxy/haproxy.cfg
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    maxconn     4000
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

    # utilize system-wide crypto-policies
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-server-ciphers PROFILE=SYSTEM

defaults
    mode                    http
    log                     global
    option                  dontlognull
    option http-server-close
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000
listen stats
    bind :9000
    mode http
    stats enable
    stats uri /
    monitor-uri /bastion-test
    stats refresh 5s

EOF

##### 6443
/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
listen api-server-6443
  bind *:6443
  mode tcp
  server bootstrap bootstrap.${CL}.${DO}:6443 check inter 1s backup 
EOF


NUM=1
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *master* ]] && continue
    read -ra col <<< "$line"
    NODENAME=${col[0]}
    NODEROLE=${col[1]}
    NODEIP=${col[2]}
    NODEGW=${col[3]}
    NODEMAC=${col[4]}
    SLAVE=${col[5]}

/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
  server ${NODEROLE}${NUM} ${NODENAME}:6443 check inter 1s
EOF
    ((NUM++))
done < hosts.txt

##### 22623
/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
listen machine-config-server-22623
  bind *:22623
  mode tcp
  server bootstrap bootstrap.${CL}.${DO}:22623 check inter 1s backup 
EOF

NUM=1
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *master* ]] && continue
    read -ra col <<< "$line"
    NODENAME=${col[0]}
    NODEROLE=${col[1]}
    NODEIP=${col[2]}
    NODEGW=${col[3]}
    NODEMAC=${col[4]}
    SLAVE=${col[5]}

/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
  server ${NODEROLE}${NUM} ${NODENAME}:22623 check inter 1s
EOF
    ((NUM++))
done < hosts.txt


##### 443
/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
listen ingress-router-443 
  bind *:443
  mode tcp
  balance source
EOF
HAS_WORKER_INFRA=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" == *worker* || "$line" == *infra* ]]; then
        HAS_WORKER_INFRA=1
        break
    fi
done < hosts.txt

NUM=1
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if (( HAS_WORKER_INFRA )); then
        [[ "$line" != *worker* && "$line" != *infra* ]] && continue
    else
        [[ "$line" != *master* ]] && continue
    fi
    read -ra col <<< "$line"
    NODENAME=${col[0]}
    NODEROLE=${col[1]}
    NODEIP=${col[2]}
    NODEGW=${col[3]}
    NODEMAC=${col[4]}
    SLAVE=${col[5]}

/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
  server ${NODEROLE}${NUM} ${NODENAME}:443 check inter 1s
EOF
    ((NUM++))
done < hosts.txt

###### 80
/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
listen ingress-router-80 
  bind *:80
  mode tcp
  balance source
EOF
NUM=1
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if (( HAS_WORKER_INFRA )); then
        [[ "$line" != *worker* && "$line" != *infra* ]] && continue
    else
        [[ "$line" != *master* ]] && continue
    fi
    read -ra col <<< "$line"
    NODENAME=${col[0]}
    NODEROLE=${col[1]}
    NODEIP=${col[2]}
    NODEGW=${col[3]}
    NODEMAC=${col[4]}
    SLAVE=${col[5]}

/bin/cat << EOF >> /etc/haproxy/haproxy.cfg
  server ${NODEROLE}${NUM} ${NODENAME}:80 check inter 1s
EOF
    ((NUM++))
done < hosts.txt


systemctl enable --now haproxy
systemctl status haproxy --no-pager
}
########################################################

####################### tftp setting ###################
function tftp_install {
mkdir -p /tftpboot/pxelinux.cfg
cp /usr/share/syslinux/pxelinux* /tftpboot/
cp /usr/share/syslinux/*c32 /tftpboot

cp /usr/lib/systemd/system/tftp.service /etc/systemd/system/tftp.service
cp /usr/lib/systemd/system/tftp.socket /etc/systemd/system/tftp.socket
cp /media/EFI/BOOT/grubx64.efi /tftpboot/grubx64.efi
chmod +r /tftpboot/grubx64.efi
/bin/cat<< EOF > /etc/systemd/system/tftp.service 
[Unit]
Description=Tftp Server
Requires=tftp.socket
Documentation=man:in.tftpd

[Service]
ExecStart=/usr/sbin/in.tftpd -s /tftpboot
StandardInput=socket

[Install]
Also=tftp.socket
EOF

systemctl enable --now tftp.socket
systemctl status tftp.socket --no-pager
}
#######################################################
################### grub menu setting default #################
function grub_menu { 


	if test -d /tftpboot ;then
		rm -rf /tftpboot/pxelinux.cfg/*
		rm -rf /tftpboot/grubcfg/*
		mkdir -p /tftpboot/pxelinux.cfg
		mkdir -p /tftpboot/grubcfg
	fi

	while IFS= read -r line; do
		    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

		        read -ra col <<< "$line"
			NODENAME=${col[0]}
			NODEROLE=${col[1]}
			NODEIP=${col[2]}
			NODEGW=${col[3]}
			NODEMAC=${col[4]}

			if [ ${NODEROLE} == "infra" ];then
					NODEROLE="worker"
				fi

				MAC=$(echo ${NODEMAC} |sed 's/:/-/g' )

				#/bin/cat << EOF >> /tftpboot/pxelinux.cfg/01-${NODEMAC}
				/bin/cat << EOF >> /tftpboot/pxelinux.cfg/01-${MAC}
DEFAULT 1
LABEL 1
MENU LABEL ${NODENAME}
     KERNEL http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64
     APPEND initrd=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:ens3:none nameserver=${BASTIONIP}
EOF
                    
/bin/cat << EOF >> /tftpboot/grubcfg/${NODEMAC}
set default="0"
menuentry '${NODENAME}' {
     linux http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64 nomodeset rd.neednet=1 ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:ens3:none nameserver=${BASTIONRIP1} coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign
     initrd fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img
}
EOF
echo 
done < hosts.txt
}
#################################################################


################### grub menu setting for vlan #################
function grub_vlan { 


if test -d /tftpboot ;then
rm -rf /tftpboot/pxelinux.cfg/*
rm -rf /tftpboot/grubcfg/*
mkdir -p /tftpboot/pxelinux.cfg
mkdir -p /tftpboot/grubcfg
fi

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    read -ra col <<< "$line"
NODENAME=${col[0]}
NODEROLE=${col[1]}
NODEIP=${col[2]}
NODEGW=${col[3]}
NODEMAC=${col[4]}
IFACE=${col[5]}


if [ ${NODEROLE} == "infra" ];then
	NODEROLE="worker"
fi

MAC=$(echo ${NODEMAC} |sed 's/:/-/g' )
if [[ "$NODEROLE" == "bootstrap" || "$NODEROLE" == "master" ]]; then
/bin/cat << EOF >> /tftpboot/pxelinux.cfg/01-${MAC}
DEFAULT 1
LABEL 1
MENU LABEL ${NODENAME}
     KERNEL http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64
     APPEND initrd=http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:${IFACE}:none nameserver=${BASTIONIP}
EOF

/bin/cat << EOF >> /tftpboot/grubcfg/${NODEMAC}
set default="0"
menuentry '${NODENAME}' {
     linux http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64 nomodeset rd.neednet=1 ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:${IFACE}:none nameserver=${BASTIONRIP1} coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign
     initrd fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img
}
EOF
    elif [[ "$NODEROLE" == "worker" ]]; then
/bin/cat << EOF >> /tftpboot/pxelinux.cfg/01-${MAC}
DEFAULT 1
LABEL 1
MENU LABEL ${NODENAME}
     KERNEL http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64
     APPEND initrd=http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign bond=bond0:${IFACE}:mode=active-backup,miimon=100 vlan=bond0.300:bond0 ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:bond0.300:none nameserver=${BASTIONIP}
EOF
                    
/bin/cat << EOF >> /tftpboot/grubcfg/${NODEMAC}
set default="0"
menuentry '${NODENAME}' {
     linux http://${PXEBASTION}:8080/fedora-coreos-39.20231101.3.0-live-kernel-x86_64 nomodeset rd.neednet=1 bond=bond0:${IFACE}:mode=active-backup,miimon=100 vlan=bond0.300:bond0 ip=${NODEIP}::${NODEGW}:255.255.255.0:${NODENAME}:bond0.300:none nameserver=${BASTIONRIP1} coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://${BASTIONRIP1}:8080/fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img coreos.inst.ignition_url=http://${BASTIONRIP1}:8080/${NODEROLE}.ign
     initrd fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img
}
EOF
	fi

echo 
done < hosts.txt
}

function dhcp_install {
	/bin/cat << EOF > /etc/dhcp/dhcpd.conf
option architecture-type code 93 = unsigned integer 16; #RFC4578
option routers     ${PXENET}.1;
option subnet-mask 255.255.255.0;


subnet ${PXENET}.0 netmask 255.255.255.0 {
  pool {
    range ${PXENET}.14  ${PXENET}.253;
EOF

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    read -ra col <<< "$line"
NODENAME=${col[0]}
NODEROLE=${col[1]}
NODEIP=${col[2]}
NODEGW=${col[3]}
NODEMAC=${col[4]}
LAST_OCTET="${NODEIP##*.}"


	/bin/cat << EOF >> /etc/dhcp/dhcpd.conf
host ${NODENAME} {
hardware ethernet ${NODEMAC};
fixed-address ${PXENET}.${LAST_OCTET};
option host-name "${NODENAME}";
}
EOF
done < hosts.txt

	/bin/cat << EOF >> /etc/dhcp/dhcpd.conf
    deny all clients;

    # this is PXE specific
    if option architecture-type = 00:07 {
	filename "grubx64.efi";
    } else {
	filename "pxelinux.0";
    }
    next-server ${PXEBASTION};
  }
}
EOF

systemctl restart dhcpd tftp.socket haproxy named httpd

}
########################################################



######################## keepalived ####################
function keepalived_install {
rpm -qa keepalived > /dev/null 2>&1

if [ $? -eq 0 ]; then
	echo
	echo "keepalived already installed."
	echo ""
        continue
else

dnf install -y keepalived 


fi

cat <<EOF>/etc/keepalived/keepalived.conf
vrrp_script check_haproxy
{
    script "/usr/bin/systemctl is-active --quiet haproxy"
    interval 5
    fall 2
    rise 2
}
vrrp_instance OCP {
    state BACKUP
    interface ens3.300
    virtual_router_id 100
    priority 200
    advert_int 5
    nopreempt
    virtual_ipaddress {
    ${BASTIONIP}/24
    }
    track_script
    {
        check_haproxy
    }

    notify_master /etc/keepalived/start.sh
    notify_backup /etc/keepalived/start.sh
    notify_fault /etc/keepalived/start.sh
}
EOF

cat <<EOF>/etc/keepalived/start.sh
#!/bin/sh

systemctl start haproxy
systemctl start named
systemctl start docker-registry
systemctl start chronyd
EOF

chmod +x /etc/keepalived/start.sh
}
########################################################

################## make_certification ##################
function make_cert {
export NAME=${CLUSTER}'.'${DOMAIN}

if ! test -d certs ; then
mkdir certs
fi

if test -f certs/ca.crt ;then
echo "CRT FILE already exists."
exit 1
fi

openssl req -newkey rsa:4096  -nodes -sha256 -keyout certs/ca.key -x509 -days 36500 -out certs/ca.crt -subj "/C=KR/ST=Seoul/L=Seoul/CN=*.apps.${NAME}" -addext "subjectAltName = DNS:*.apps.${NAME}, DNS:*.${NAME}"

openssl genpkey -algorithm RSA -out certs/tls.key

openssl req -new -key certs/tls.key -out certs/tls.csr -subj "/C=KR/ST=Seoul/L=Seoul/CN=*.apps.${NAME}" -addext "subjectAltName=DNS:*.apps.${NAME},DNS:*.${NAME}"

extfile="$(mktemp)"
trap 'rm -f "$extfile"' EXIT

printf '%s\n' "subjectAltName = DNS:*.apps.${NAME}, DNS:*.${NAME}" > "$extfile"

openssl x509 -req \
  -in certs/tls.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/tls.crt \
  -days 36500 -sha256 \
  -extfile "$extfile"

#####openssl x509 -req -in certs/tls.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial -out certs/tls.crt -days 36500 -sha256 -extfile <(printf "subjectAltName = DNS:*.apps.${NAME}, DNS:*.${NAME}")

cp certs/ca.crt /etc/pki/ca-trust/source/anchors/
cp certs/tls.crt /etc/pki/ca-trust/source/anchors/

ls /etc/pki/ca-trust/source/anchors/

}


########################################################


##################docker registry ######################
function docker_registry {
REGDIR=/opt/registry
NFSIP=${PXENET}.1

mkdir -p /opt/registry

mount -t nfs ${NFSIP}:/ /opt/registry

if ! test -d /opt/registry/data ; then
  mkdir -p /opt/registry/{data,certs,auth}
#  tar xvf /ocp/ocp-4.14.17-default.tar -C /opt/registry
fi

podman load --input docker.io_library_registry_2.8.3.tar
podman images |grep 26b2eb03618e|awk '{print $2}'
echo

REGISTRY_TAG=2.8.3
podman tag 26b2eb03618e docker.io/registry:${REGISTRY_TAG}

cp certs/ca.crt /opt/registry/certs/domain.crt
cp certs/ca.key /opt/registry/certs/domain.key


SELINUX=$(cat /etc/selinux/config |grep '^SELINUX=' | cut -d '=' -f2)

if [  ${SELINUX} == "disabled" ] ; then
  podman run --name registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry -v /opt/registry/certs:/certs -v /etc/hosts:/etc/hosts -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -d docker.io/registry:${REGISTRY_TAG}
else
  podman run --name registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/certs:/certs:z -v /etc/hosts:/etc/hosts:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -d docker.io/registry:${REGISTRY_TAG}
fi

podman ps
echo
curl -k https://${HOST}.${CLUSTER}.${DOMAIN}:5000/v2/_catalog


podman generate systemd --name $(podman ps --all|awk '{print $NF}'|grep -v NAMES) > /etc/systemd/system/docker-registry.service
}
########################################################
function extract_command {
tar xf  openshift-client-linux-amd64-rhel8-4.18.0-okd-scos.10.tar.gz -C /usr/local/bin/.
tar xf  openshift-install-linux-4.18.0-okd-scos.10.tar.gz -C /usr/local/bin/.
}

#######################################################


#####################ssh-key create ###################
function ssh_key {
ssh-keygen -t rsa -b 4096
}
#######################################################


#######################################################
function install_config {

A=$HOST
B=$CLUSTER
C=$DOMAIN
D=$(cat /root/.ssh/id_rsa.pub)

cat certs/ca.crt > certs/ca_bk.crt
sed -i 's/^/  /g' certs/ca_bk.crt
E=$(cat certs/ca_bk.crt)

/bin/cat << EOF > ./install-config.yaml
apiVersion: v1
baseDomain: ${C}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1
metadata:
  name: ${B}
networking:
  clusterNetworks:
  - cidr: 128.0.0.0/8
    hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.21.0.0/16
platform:
  none: {}
pullSecret: '{"auths":{"${A}.${B}.${C}:5000":{"auth":"YWRtaW46YWRtaW4="}}}'
sshKey: '${D}'
additionalTrustBundle: |
${E} 

imageContentSources:
- mirrors:
  - ${A}.${B}.${C}:5000/ocp4/openshift4
  source: quay.io/openshift/okd
- mirrors:
  - ${A}.${B}.${C}:5000/ocp4/openshift4
  source: quay.io/openshift/okd-content
EOF

cp ./install-config.yaml ./install-config.yaml.bk


#cat /etc/bashrc |grep kubeconfig
#BASHRC=$?

#if [ ${BASHRC} != 0  ]; then
#echo "export KUBECONFIG=/ocp/auth/kubeconfig" >> /etc/bashrc
#echo "relogin please"
#fi
}

#######################################################
function pull_secret {
A=${HOST}
B=${CLUSTER}.${DOMAIN}

/bin/cat << EOF > pull-secret.txt
{"auths":{"cloud.openshift.com":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMWNmNWRiMDg5M2U2NGU5NDljYmRiMzEwYWVjZWQ0YTA6QVlOOURRWVpQSEVWOFZJMUI1VzQ5MDA5U1dXU1QyOTJWRDdOSVdUSEdGOUIxWjk5M1JGRFdITzNSVFVFTkc3Ng==","email":"joo@growin.co.kr"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMWNmNWRiMDg5M2U2NGU5NDljYmRiMzEwYWVjZWQ0YTA6QVlOOURRWVpQSEVWOFZJMUI1VzQ5MDA5U1dXU1QyOTJWRDdOSVdUSEdGOUIxWjk5M1JGRFdITzNSVFVFTkc3Ng==","email":"joo@growin.co.kr"},"registry.connect.redhat.com":{"auth":"fHVoYy1wb29sLWI1NzY4MjdjLTM4ZWMtNDg4MS04NjYxLTc5NWIxYjdmMmQ5YjpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSXlZbU01TkRrMU1tVXlORE0wTkRFek9UTTJaRGRpWkRGaVptVXlZamcyWXlKOS5DTEpTaWRTeFFEOUNpTm92VWd6Tkt6TFl2cThHN3c3V0c0cnRUVFF5RFEtenkxWURyREVpd3hITHhUSmtQc3gtRlZrNkFHQ0FfUzNjelQxX1dfN3lNRzVVWGxwdGI1X002bm1KRGtBVnJiVldCNTRHdDlZcmFWNFVxZW9OYmxSLThhUUU5ZjBlUFZLNTEzaHplU0g0dUQyVHdOR1BKSzNKZ0tRVlR6cWdYeHNkNllSMW1ORzdjTTJ6RmZhY2dqeUEzZUNhRDU1Uko3dlBXSjdremVwLUNzN2FLZlFsemlFWVhtY1JlUW1LaGZGOU1iTHlYXzd1dzNfMjdfS0xTc0FvcjBqdzAxXzg4ZWgxbmdTbGdxZkVGd2NuclgtVFpnTEYtenpxT0VUTkhTck9oV0ZzVUNRVzNnb18tcW15MFdGZk9UaHljbnIzUG1OenJneE1uNzhZMHppcVFOOTVvM29rZ1c0XzFVOGRuY0s0Y3BjV3RCQlVuQTNnQS1uemJCY2dwUExLSWV6cFpRclNpd1RwVWo4QkpYZXpOazhwMllJaHpfSWxiNDZuWTk0dTBCX1RqMjdpNEpucndIbEJkTHpsMk9lV0RGX3hLbkFiSWdjV24tRUtYMmJ6NDliSWs1TzNHakR4cEF0QmdXLU9IQjZoVWpyMEFxR01HZm9YRVFTS3NHQTY0RGd4Z0R2Sl90WHhVcml3TXlRTXVubGdhM0cyUGxfRVAwZ0xsUXZsdl9SNGZmazh1UXRra1Z2dTRsaEx0YXhGV21jM25FNG1TSThYcFgwTFdNckd2bmFuT2Q2SmpPb05fcXRReTRHRS0tQU9KTWY1dldrVFhtT3VpZVlNNjdLeWtXWVRYUG53aGFUMk5RWWlUY0dPSzVDdG9TTm5EdHo0dHBRVnMwbw==","email":"joo@growin.co.kr"},"registry.redhat.io":{"auth":"fHVoYy1wb29sLWI1NzY4MjdjLTM4ZWMtNDg4MS04NjYxLTc5NWIxYjdmMmQ5YjpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSXlZbU01TkRrMU1tVXlORE0wTkRFek9UTTJaRGRpWkRGaVptVXlZamcyWXlKOS5DTEpTaWRTeFFEOUNpTm92VWd6Tkt6TFl2cThHN3c3V0c0cnRUVFF5RFEtenkxWURyREVpd3hITHhUSmtQc3gtRlZrNkFHQ0FfUzNjelQxX1dfN3lNRzVVWGxwdGI1X002bm1KRGtBVnJiVldCNTRHdDlZcmFWNFVxZW9OYmxSLThhUUU5ZjBlUFZLNTEzaHplU0g0dUQyVHdOR1BKSzNKZ0tRVlR6cWdYeHNkNllSMW1ORzdjTTJ6RmZhY2dqeUEzZUNhRDU1Uko3dlBXSjdremVwLUNzN2FLZlFsemlFWVhtY1JlUW1LaGZGOU1iTHlYXzd1dzNfMjdfS0xTc0FvcjBqdzAxXzg4ZWgxbmdTbGdxZkVGd2NuclgtVFpnTEYtenpxT0VUTkhTck9oV0ZzVUNRVzNnb18tcW15MFdGZk9UaHljbnIzUG1OenJneE1uNzhZMHppcVFOOTVvM29rZ1c0XzFVOGRuY0s0Y3BjV3RCQlVuQTNnQS1uemJCY2dwUExLSWV6cFpRclNpd1RwVWo4QkpYZXpOazhwMllJaHpfSWxiNDZuWTk0dTBCX1RqMjdpNEpucndIbEJkTHpsMk9lV0RGX3hLbkFiSWdjV24tRUtYMmJ6NDliSWs1TzNHakR4cEF0QmdXLU9IQjZoVWpyMEFxR01HZm9YRVFTS3NHQTY0RGd4Z0R2Sl90WHhVcml3TXlRTXVubGdhM0cyUGxfRVAwZ0xsUXZsdl9SNGZmazh1UXRra1Z2dTRsaEx0YXhGV21jM25FNG1TSThYcFgwTFdNckd2bmFuT2Q2SmpPb05fcXRReTRHRS0tQU9KTWY1dldrVFhtT3VpZVlNNjdLeWtXWVRYUG53aGFUMk5RWWlUY0dPSzVDdG9TTm5EdHo0dHBRVnMwbw==","email":"joo@growin.co.kr"},"${A}.${B}:5000":{"auth":"YWRtaW46YWRtaW4="}}}
EOF
}

#######################################################


function cluster_create {
INSTALLDIR='install_'$(date +%Y%m%d)
mkdir ${INSTALLDIR}


cp install-config.yaml ${INSTALLDIR}/install-config.yaml

openshift-install create manifests --dir ${INSTALLDIR}

#sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g'  ${INSTALLDIR}/manifests/cluster-scheduler-02-config.yml
#sed -i 's/true/false/g' ${INSTALLDIR}/manifests/cluster-scheduler-02-config.yml

cp mc/*.yaml ${INSTALLDIR}/openshift

openshift-install create ignition-configs --dir ${INSTALLDIR}

chmod +r ${INSTALLDIR}/*ign

\cp -arp ${INSTALLDIR}/*.ign /var/www/html/.
systemctl restart httpd
echo openshift-install wait-for bootstrap-complete --dir=${INSTALLDIR} --log-level=debug



cp ${INSTALLDIR}/auth/kubeconfig /root/.kube/config
#unlink /root/.kube/config
#ln -s /root/.kube/config_kj /root/.kube/config
#sed  -i '/KUBEPW/d' /root/.bash_profile
#echo 'KUBEPW='$(cat /root/${DIR}/auth/kubeadmin-password) >> /root/.bash_profile
#echo 'export KUBEPW' >> /root/.bash_profile

}


########################################################

######################## oc complete ###################
function oc_complete {
oc completion bash > /etc/bash_completion.d/oc_completion.bash
echo source /etc/bash_completion.d/oc_completion.bash >> ~/.bash_profile
source ~/.bash_profile
}


######################## run script ####################
#etchosts
#localrepo
#iso_mount
#install_pkg 
#daemon_arrange 
#disable_selinux 
#disable_fw 
dns_install 
haproxy_install 
#tftp_install 
#grub_menu 
#grub_vlan
#dhcp_install 
keepalived_install 
#make_cert 
#docker_registry 
#extract_command 
#ssh_key 
#install_config 
#pull_secret 
#cluster_create 
#oc_complete
