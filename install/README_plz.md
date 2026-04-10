## 현재 해당 툴은 LGU+ 대전 사옥 cpm01 (amf) 기준으로 작성되어있음
# 설치 후에 해야하는 것.
OKD offline 설치환경의 경우 bootstrap 62011 커맨드 돌릴것.
named에 bastion, bastion1 bastion2 등 추가 , hosts에 마찬가지로 shortname 추가.

# 필수 변경해야하는 변수 (파일명 / 변수명) 

bastion.env / ROOT_PASSWORD
bastion.env / EXTRA_USER_PASSWORD
bastion.env / OC_LOGIN_PASSWORD
bastion.env / OC_LOGIN_SERVER


cluster.env / HOST
cluster.env / CLUSTER_NAME
cluster.env / BASE_DOMAIN


install-config.env / MC_INIT_ENABLE
install-config.env / MC_INIT_COPY_TO_MANIFESTS
install-config.env / MC_ENABLE_CHRONY=yes
install-config.env / MC_ENABLE_REGISTRIES=yes
install-config.env / MC_ENABLE_CORE_PASSWORD=yes
install-config.env / MC_ENABLE_ROOT_PASSWORD=yes
install-config.env / MC_ENABLE_THP=no

install-config.env / MC_CORE_PASSWORD='telco1234'
install-config.env / MC_ROOT_PASSWORD='telco1234'

install-config.env / MC_THP_ISOLCPUS="${MC_THP_ISOLCPUS:-}"
install-config.env / MC_THP_HUGEPAGESZ=1G
install-config.env / MC_THP_HUGEPAGES=128
install-config.env / MC_THP_DISABLE_TRANSPARENT_HUGEPAGE=no



network.env / SERVICE_VIP
network.env / INGRESS_VIP
network.env / DNS_SERVER
network.env / NTP_SERVERS
network.env / ALLOW_NETWORKS
이하 네트워크 관련 변수는 환경에맞춰 수정




## VM 생성명령어 (LGU 대전 작업 기준으로 작성됨)
#AMF (cpm01)#
virt-install   --name dj-tw-mano-cpm01-vm-bastion01   --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bastion1.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:6F:23:8A  --network bridge=br-oam,model=virtio --network bridge=br-ilo,model=virtio --noautoconsole --import
virt-install   --name dj-tw-mano-cpm01-vm-bastion02   --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bastion2.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:D1:4B:77  --network bridge=br-oam,model=virtio --network bridge=br-ilo,model=virtio --noautoconsole --import
qemu-img create -f qcow2 /home/vmimg/bootstrap.qcow2 200G
qemu-img create -f qcow2 /home/vmimg/master2.qcow2 200G
qemu-img create -f qcow2 /home/vmimg/master3.qcow2 200G
virt-install   --name dj-tw-mano-cpm01-vm-bootstrap  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bootstrap.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:3A:7F:91   --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm01-vm-mst01  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master1.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:B2:1C:4E  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm01-vm-mst02  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master2.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:8D:55:A7  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm01-vm-mst03  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master3.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:19:E3:6B  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &



#SMF (cpm02)#
virt-install   --name dj-tw-mano-cpm02-vm-bastion01   --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bastion1.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:0C:9E:52 --network bridge=br-oam,model=virtio --noautoconsole --import
virt-install   --name dj-tw-mano-cpm02-vm-bastion02   --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bastion2.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:A8:35:1D --network bridge=br-oam,model=virtio --noautoconsole --import
qemu-img create -f qcow2 /home/vmimg/bootstrap.qcow2 200G
qemu-img create -f qcow2 /home/vmimg/master1.qcow2 200G
qemu-img create -f qcow2 /home/vmimg/master2.qcow2 200G
qemu-img create -f qcow2 /home/vmimg/master3.qcow2 200G
virt-install   --name dj-tw-mano-cpm02-vm-bootstrap  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/bootstrap.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:CF:02:9D   --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm02-vm-mst01  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master1.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:74:AA:38  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm02-vm-mst02  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master2.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:5E:90:C1  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
virt-install   --name dj-tw-mano-cpm02-vm-mst03  --vcpus 24   --memory 32768   --cpu host-passthrough   --disk path=/home/vmimg/master3.qcow2,format=qcow2,bus=virtio   --network bridge=br-k8s,model=virtio,mac=52:54:00:2B:D6:F4  --network bridge=br-oam,model=virtio  --noautoconsole --boot bootmenu.enable=on --osinfo detect=on,require=off --pxe --wait &
