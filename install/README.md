# install

## 목적

`install/`은 OpenShift/OKD **UPI 설치용 bastion 자동화 도구**입니다.

주요 목표는 다음과 같습니다.

- bastion 사전 준비 자동화
- install-config / manifests / ignition 생성 자동화
- registry / dns / haproxy / dhcp / tftp / pxe-grub 준비 자동화
- OKD(FCOS)와 OCP(RHCOS)를 모두 수용할 수 있는 범용 구조 제공
- single bastion / dual bastion(keepalived) 분기 지원

현재 기본 설계는 **UPI(`platform: none`) 기준**입니다.

---

# 단계 구분

## 1. pre
bastion에서 설치 준비에 필요한 서비스와 설정을 구성합니다.

대상:
- command extract
- selinux
- bastion account
- chrony
- cert
- registry
- hosts
- dns
- haproxy
- tftp
- dhcp
- pxe/grub
- keepalived

실행:
```bash
bash run.sh pre
```

---

## 2. install
OpenShift installer 기반 산출물을 생성하고, 이를 bastion에 publish 합니다.

대상:
- install-config.yaml 생성
- manifests 생성
- ignition 생성
- COS artifacts publish

실행:
```bash
bash run.sh install
```

---

## 3. post
클러스터 설치 이후 OpenShift 리소스를 후처리합니다.

대상 예:
- ingress
- routingViaHost
- user workload monitoring
- catalog source
- 기타 post patch

실행:
```bash
bash run.sh post
```

---

# 디렉토리 구조

예시:

```text
install/
├── 00-vars/
│   ├── bastion.env
│   ├── cluster.env
│   ├── install-config.env
│   ├── network.env
│   ├── post.env
│   └── registry.env
├── 00-inventory/
│   └── hosts.txt
├── 01-pre/
├── 02-install/
├── 03-post/
├── cos/
├── templates/
├── lib/
└── run.sh
```

---

# 실행 전 준비

## 1. ISO mount

PXE/GRUB 구성 시 `/media`에 ISO가 mount 되어 있어야 합니다.

예:
```bash
mount -o loop <iso-file>.iso /media
```

필수 파일:
```text
/media/EFI/BOOT/grubx64.efi
```

이 파일이 없으면 GRUB EFI 관련 단계가 실패할 수 있습니다.

---

## 2. COS 파일 준비

OKD는 FCOS, OCP는 RHCOS를 사용하지만, 이 툴에서는 둘 다 **COS**라는 중립적 표현으로 다룹니다.

`install/cos/` 아래에 kernel / initramfs / rootfs 파일을 넣어두면 됩니다.

예시:
```text
install/cos/
├── fedora-coreos-39.20231101.3.0-live-kernel-x86_64
├── fedora-coreos-39.20231101.3.0-live-initramfs.x86_64.img
└── fedora-coreos-39.20231101.3.0-live-rootfs.x86_64.img
```

또는:
```text
install/cos/
├── rhcos-live-kernel-x86_64
├── rhcos-live-initramfs.x86_64.img
└── rhcos-live-rootfs.x86_64.img
```

파일명은 고정이 아닙니다.  
각각 이름에 아래 문자열이 하나씩 포함되어 있으면 됩니다.

- `kernel`
- `initramfs`
- `rootfs`

동일 문자열을 포함한 파일이 2개 이상이면 실패합니다.

---

## 3. inventory 준비

`00-inventory/hosts.txt` 포맷:

```text
# hostname role ip gateway nic mac nettype vlan_id install_dev
bastion.test.okd bastion 100.230.0.235 100.230.0.1 eno3 52:54:00:21:f8:10 ethernet - /dev/vda
bootstrap.test.okd bootstrap 100.230.0.237 100.230.0.1 eno3 52:54:00:61:ca:82 ethernet - /dev/vda
master1.test.okd master 100.230.0.238 100.230.0.1 eno3 52:54:00:3f:32:db ethernet - /dev/vda
master2.test.okd master 100.230.0.239 100.230.0.1 eno3 52:54:00:6d:e2:53 ethernet - /dev/vda
master3.test.okd master 100.230.0.240 100.230.0.1 eno3 52:54:00:c7:f6:bb ethernet - /dev/vda
worker1.test.okd worker 100.230.0.2 100.230.0.1 ens3f1,ens9f1 6c:83:75:bb:e0:a1 bond - /dev/vda
```

규칙:
- 1컬럼은 **반드시 FQDN**
- `role`은 `bastion`, `bootstrap`, `master`, `worker`, `infra`
- `nettype`은 `ethernet`, `vlan`, `bond`
- `install_dev`가 `-`면 role 기준 기본값 사용

---

# 변수 명세

## 00-vars/cluster.env

### 주요 변수

- `HOST`
  - bastion shortname
- `CLUSTER_NAME`
  - 클러스터 이름
- `BASE_DOMAIN`
  - base domain
- `API_SERVER`
  - API endpoint 기본값
- `BASTION_HOST_PATTERN`
  - bastion host 식별용

### 예시
```bash
HOST="bastion"
CLUSTER_NAME="test"
BASE_DOMAIN="okd"
```

생성되는 기본 FQDN:
```text
bastion.test.okd
```

---

## 00-vars/network.env

### 주요 변수

- `PXE_BASTION_IP`
- `SERVICE_VIP`
- `INGRESS_VIP`
- `DNS_SERVER`
- `PXE_NETMASK`
- `NIC_NAME`
- `VLAN_ID`

### 동작 분기

#### A. bastion 수가 1개일 때
- keepalived 미적용
- PXE/GRUB `nameserver` = `PXE_BASTION_IP`
- DNS `api`, `api-int`, `*.apps` = `PXE_BASTION_IP`

#### B. bastion 수가 2개 이상일 때
- keepalived 적용 가능
- PXE/GRUB `nameserver` = `DNS_SERVER`
- DNS `api`, `api-int`, `*.apps` = VIP

즉:

- `bastion count = 1` → single mode
- `bastion count >= 2` → HA mode

---

## 00-vars/registry.env

### 주요 변수

- `REGISTRY_CONTAINER_PORT`
- `BASE_REGISTRY_IMAGE`
- `CERT_DIR`
- `CERT_FILE`
- `KEY_FILE`
- `CERT_IF_EXISTS`
- `REGISTRY_TAR_FILE`
- `REGISTRY_TAG`
- `REGISTRIES_CSV`

### REGISTRIES_CSV 예시

```bash
REGISTRIES_CSV="infra_registry|/NFS/infra_registry|5000,cnf_registry|/NFS/cnf_registry|5001"
```

### CERT_IF_EXISTS 동작 분기

#### `CERT_IF_EXISTS=fail`
기존 cert가 있으면 실패

#### `CERT_IF_EXISTS=skip`
기존 cert가 있으면 생성 생략

#### `CERT_IF_EXISTS=replace`
기존 cert 백업 후 재생성

---

## 00-vars/bastion.env

### 주요 변수

- `CREATE_EXTRA_USER`
- `EXTRA_USER_NAME`
- `EXTRA_USER_GROUPS`
- `EXTRA_USER_SUDO_NOPASSWD`
- `ENABLE_OC_AUTO_LOGIN`
- `OC_LOGIN_USER`
- `OC_LOGIN_PASSWORD`
- `OC_LOGIN_SERVER`

### 동작 분기

#### `CREATE_EXTRA_USER=yes`
추가 사용자 생성

#### `ENABLE_OC_AUTO_LOGIN=yes`
`.bashrc`에 자동 로그인 구문 추가

---

## 00-vars/install-config.env

### 주요 변수

- `INSTALL_BASE_DIR`
- `INSTALL_WORKDIR`
- `SOURCE_INSTALL_CONFIG_FILE`
- `INSTALL_CONFIG_FILE`
- `OPENSHIFT_INSTALL_BIN`
- `PULL_SECRET_FILE`
- `SSH_PUBKEY_FILE`
- `ADDITIONAL_TRUST_BUNDLE_FILE`
- `REGISTRY_HOSTNAME`
- `CONTROL_PLANE_REPLICAS`
- `COMPUTE_REPLICAS`
- `CLUSTER_NETWORK_CIDR`
- `CLUSTER_NETWORK_HOST_PREFIX`
- `SERVICE_NETWORK_CIDR`
- `INSTALL_PLATFORM`
- `NETWORK_TYPE`
- `IMAGE_MIRROR_HOST`
- `IMAGE_MIRROR_PATH`
- `IMAGE_SOURCE_RELEASE`
- `IMAGE_SOURCE_CONTENT`
- `COS_SOURCE_DIR`
- `COS_KERNEL_MATCH`
- `COS_INITRAMFS_MATCH`
- `COS_ROOTFS_MATCH`

### 기본 install 경로

기본값:
```text
/root/growin/install_YYYYMMDD
```

### install-config 원본 / 복사본

원본:
```text
/root/growin/install-config.yaml
```

작업용 복사본:
```text
/root/growin/install_YYYYMMDD/install-config.yaml
```

원본은 계속 유지하고, installer는 복사본을 소비합니다.

### INSTALL_PLATFORM 동작 분기

#### `INSTALL_PLATFORM=none`
- UPI
- `create cluster` 수행 안 함
- ignition/artifacts 생성까지만 수행

---

# pre 단계 상세

## 01-pre/00-command-extract.sh
역할:
- `helm`, `oc`, `kubectl`, `openshift-install` 설치

동작:
- tar에서 바이너리 추출
- 버전이 같으면 skip

---

## 01-pre/01-disable-selinux.sh
역할:
- SELinux disable 설정

---

## 01-pre/02-bastion-account.sh
역할:
- 사용자 생성
- sudoers 구성
- `.bashrc` path/oc login 구성

---

## 01-pre/03-bastion-chrony.sh
역할:
- chrony 설정 및 시작

---

## 01-pre/04-make-certs.sh
역할:
- cert 생성
- 필요 시 trust 등록

분기:
- `CERT_IF_EXISTS=fail|skip|replace`

---

## 01-pre/05-registry.sh
역할:
- registry container 생성
- systemd 등록
- enable/start

주의:
- health check curl은 DNS 순서 의존을 만들 수 있으므로 제거된 구조가 적합

---

## 01-pre/06-hosts-render.sh
역할:
- `/etc/hosts` 갱신

동작:
- `# BEGIN_GROWIN_HOSTS` ~ `# END_GROWIN_HOSTS` 블록만 관리
- FQDN inventory 기준
  ```text
  IP FQDN shortname
  ```

예:
```text
100.230.0.238 master1.test.okd master1
```

---

## 01-pre/07-dns-render.sh
역할:
- `named.conf`
- zone file 생성
- named restart

기본 생성 레코드:
- `ns1`
- `@`
- `api`
- `api-int`
- `*.apps`
- inventory host shortname A record

### 분기

#### bastion 수 = 1
- `api` → bastion 실제 IP
- `api-int` → bastion 실제 IP
- `*.apps` → bastion 실제 IP

#### bastion 수 >= 2
- `api` → `SERVICE_VIP`
- `api-int` → `SERVICE_VIP`
- `*.apps` → `INGRESS_VIP`

---

## 01-pre/08-haproxy-render.sh
역할:
- `/etc/haproxy/haproxy.cfg` 생성
- validate / restart

현재 포맷:
- `listen` 기반

### 백엔드 규칙

#### `6443`
- bootstrap
- master

#### `22623`
- bootstrap
- master

#### `80`
- worker
- infra

#### `443`
- worker
- infra

서버 대상은 inventory FQDN 기준

---

## 01-pre/09-tftp-install.sh
역할:
- tftp 구성
- grub EFI 파일 준비

주의:
- `/media/EFI/BOOT/grubx64.efi` 필요

---

## 01-pre/10-dhcp-render.sh
역할:
- `/etc/dhcp/dhcpd.conf` 생성
- dhcpd 시작

추가 정책 예:
```conf
deny all clients;
```

의미:
- 일반 동적 lease 거부
- reservation 기반만 허용

---

## 01-pre/11-pxe-grub-render.sh
역할:
- MAC별 PXE / GRUB 설정 파일 생성

출력:
- `/tftpboot/pxelinux.cfg/01-xx-xx-xx-xx-xx-xx`
- `/tftpboot/grub.cfg-01-xx-xx-xx-xx-xx-xx`

입력:
- inventory
- `install/cos`
- network vars

### 네트워크 분기

#### `nettype=ethernet`
```text
ip=<ip>::<gw>:<netmask>:<hostname>:<nic>:none nameserver=<ns>
```

#### `nettype=vlan`
```text
vlan=<nic>.<vlan_id>:<nic> ip=<ip>::<gw>:<netmask>:<hostname>:<nic>.<vlan_id>:none nameserver=<ns>
```

#### `nettype=bond`
```text
bond=bond0:<nic-list>:mode=active-backup,miimon=100 ip=<ip>::<gw>:<netmask>:<hostname>:bond0:none nameserver=<ns>
```

### nameserver 분기

#### bastion 수 = 1
- `nameserver=PXE_BASTION_IP`

#### bastion 수 >= 2
- `nameserver=DNS_SERVER`

### 파일 참조 규칙
- `install/cos/`에서 `kernel`, `initramfs`, `rootfs` 문자열 기준으로 파일 탐색
- 실제 basename을 그대로 사용

즉:
- publish 시 원본 파일명 유지
- PXE/GRUB도 같은 이름 참조

---

## 01-pre/12-keepalived-render.sh
역할:
- keepalived conf 생성 및 restart

### 분기

#### bastion 수 = 1
- keepalived skip
- exit 0

#### bastion 수 >= 2
- keepalived conf 생성
- 첫 번째 bastion → MASTER
- 나머지 → BACKUP

이 스크립트는 나중에 bastion 2호기 추가 후 단독 실행 가능해야 합니다.

---

# install 단계 상세

## 02-install/00-install-config-render.sh
역할:
- install-config 원본 생성
- install dir로 복사

### pull-secret 분기

1. `/root/pull-secret.json` 존재 → 사용
2. `install/pull-secret.json` 존재 → 사용
3. 둘 다 없으면 자동 생성

자동 생성 예:
```json
{"auths":{"bastion.test.okd:5000":{"auth":"YWRtaW46YWRtaW4="}}}
```

### additional trust bundle 분기

1. `ADDITIONAL_TRUST_BUNDLE_FILE` 존재 → 사용
2. 없으면 `CERT_DIR/CERT_FILE` 사용

### 출력
- 원본:
  `/root/growin/install-config.yaml`
- 복사본:
  `${INSTALL_WORKDIR}/install-config.yaml`

---

## 02-install/01-manifests-generate.sh
역할:
- `openshift-install create manifests`

중단 조건:
- `${INSTALL_WORKDIR}/manifests` 이미 존재
- `${INSTALL_WORKDIR}/openshift` 이미 존재

---

## 02-install/02-ignition-generate.sh
역할:
- `openshift-install create ignition-configs`

생성:
- `bootstrap.ign`
- `master.ign`
- `worker.ign`
- `auth/`

중단 조건:
- `auth/` already exists
- ignition files already exist

주의:
- manifests 생성 후 install-config 복사본은 소비될 수 있으므로 이 단계에서 다시 찾으면 안 됨

---

## 02-install/03-publish-artifacts.sh
역할:
- ignition publish
- COS publish

### 복사 대상
- ignition → `${IGNITION_HTTP_DIR}`
- kernel/initramfs → `${TFTP_ROOT}`
- rootfs → `${HTTP_ROOT}`

### 동작
- `install/cos/`에서 문자열 매칭으로 파일 탐색
- 원본 파일명 유지
- publish 후 PXE/GRUB에서 동일 basename 참조

---

## 02-install/04-create-cluster.sh
UPI 기준에서는 불필요  
현재 flow에서는 제외하는 것이 맞음

---

# post 단계 상세

post는 클러스터가 살아난 뒤 적용합니다.

예:
- ingress tuning
- whereabouts
- user workload monitoring
- routingViaHost
- catalog source

실행:
```bash
bash run.sh post
```

---

# install 실행 정책

## 기존 산출물 존재 시
새로 덮어쓰지 않고 즉시 종료하는 것이 원칙입니다.

중단 대상 예:
- manifests
- openshift
- auth
- bootstrap.ign
- master.ign
- worker.ign

단:
- install workdir 자체는 생성 가능
- install-config 원본은 `/root/growin/install-config.yaml`에 유지

---

# 요약 분기표

## bastion 수 = 1
- keepalived skip
- PXE nameserver = bastion 실제 IP
- DNS api/api-int/apps = bastion 실제 IP

## bastion 수 >= 2
- keepalived enable 가능
- PXE nameserver = DNS_SERVER
- DNS api/api-int/apps = VIP

## CERT_IF_EXISTS=skip
- cert already exists → 생성 안 함

## nettype=bond
- bond0
- mode=active-backup
- miimon=100

## INSTALL_PLATFORM=none
- UPI
- create cluster 안 함

---

# 권장 순서

## 1. pre
```bash
bash run.sh pre
```

## 2. install
```bash
bash run.sh install
```

## 3. PXE 부팅 및 설치 진행
- bootstrap
- masters
- workers

## 4. post
```bash
bash run.sh post
```

---

# 자주 발생하는 문제

## `/media/EFI/BOOT/grubx64.efi` 없음
원인:
- ISO mount 안 됨

조치:
```bash
mount -o loop <iso> /media
```

---

## `NS has no address records`
원인:
- `ns1` A record 없음

조치:
- zone 생성 시 `ns1 IN A <bastion-ip>` 보장

---

## `cannot create the cluster because "none" is a UPI platform`
원인:
- UPI에서 `create cluster` 실행

조치:
- 해당 단계 제거

---

## `install-config file not found` after manifests
원인:
- manifests 생성 시 install-config 복사본 소비

조치:
- ignition/create 단계에서 install-config 재검사 금지
