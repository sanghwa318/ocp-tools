# ocp-tools

OpenShift/OKD 구축 및 운영 자동화를 위한 스크립트 모음입니다.

현재 레포 기준으로 주요 영역은 다음과 같습니다.

- `backup/` : 클러스터 리소스 백업
- `image/` : 이미지 수집/미러링
- `mc_init/` : 초기 MachineConfig 리소스
- `install/01-pre/` : 배스천/사전 준비 작업
- `install/02-okd-install/` : OKD 설치용 배스천 구성 및 설치 스크립트
- `install/03-post/` : 설치 후 공통 후처리 작업

---

## Repository Structure

```text
ocp-tools/
├── README.md
├── backup/
│   ├── growin_ocp_backup.sh
│   └── growin_ocp_backup_v0.2.sh
├── image/
│   └── mirror-images.sh
├── mc_init/
│   ├── 99-master-*.yaml
│   ├── 99-worker-*.yaml
│   └── make-registry-mc.sh
└── install/
    ├── 01-pre/
    │   ├── 00-make-certs.sh
    │   ├── 01-registry.sh
    │   ├── 02-openshift-admin-user.sh
    │   ├── 03-bastion-account.sh
    │   ├── 04-command-extract.sh
    │   └── 05-bastion-chrony.sh
    ├── 02-okd-install/
    │   └── script.sh
    └── 03-post/
        ├── 06-ingress-master.sh
        ├── 07-whereabouts-reconciler.sh
        ├── 08-userWorkloadMonitoring.sh
        ├── 09-routingViaHost.sh
        └── 10-enableCatalogSources.sh
```

---

## 1. backup

클러스터 리소스 백업 스크립트입니다.

### Included scripts

#### `backup/growin_ocp_backup.sh`
기본 백업 스크립트입니다.

#### `backup/growin_ocp_backup_v0.2.sh`
병렬 처리 기반 개선 버전입니다.

### Main purpose

- namespace별 주요 리소스 수집
- cluster 범위 리소스 수집
- YAML/JSON 기반 백업
- 운영 점검 및 장애 분석용 스냅샷 확보

### Typical use

```bash
bash backup/growin_ocp_backup.sh
```

```bash
bash backup/growin_ocp_backup_v0.2.sh
```

---

## 2. image

이미지 미러링 스크립트입니다.

### `image/mirror-images.sh`

주요 기능:

- 입력 이미지 목록에서 대상 이미지 추출
- 중복 제거
- 필요한 레지스트리 자동 로그인
- 대상 레지스트리에 이미 존재하는 이미지 skip
- `skopeo copy --all` 기반 복사
- 병렬 처리
- retry 지원
- success / fail 로그 분리

### Typical use

```bash
bash image/mirror-images.sh images.txt bastion.ocp.lsh:5000 6 2 ./mirror-logs
```

인자 의미 예시:

- `images.txt` : 원본 이미지 목록 파일
- `bastion.ocp.lsh:5000` : 대상 레지스트리
- `6` : 병렬 작업 수
- `2` : 재시도 횟수
- `./mirror-logs` : 로그 디렉토리

---

## 3. mc_init

OpenShift 노드 초기 설정용 MachineConfig 리소스와 생성 스크립트입니다.

### Main purpose

- master / worker 공통 초기 설정 반영
- chrony 설정 배포
- multipath 설정 배포
- iSCSI 관련 설정 반영
- core / root 계정 비밀번호 설정
- SSH password login 허용
- timezone 설정
- worker 노드 kernel argument 설정
- registry mirror용 MachineConfig 생성

### Included files

#### master
- `99-master-chrony.yaml`
- `99-master-iscsi-scan-add.yaml`
- `99-master-multipath.yaml`
- `99-master-registries.yaml`
- `99-master-set-core-passwd.yaml`
- `99-master-set-root-passwd.yaml`
- `99-master-ssh-enable-password-login.yaml`
- `99-master-timezone.yaml`

#### worker
- `99-worker-chrony.yaml`
- `99-worker-iommu.yaml`
- `99-worker-iscsi-scan-add.yaml`
- `99-worker-multipath.yaml`
- `99-worker-registries.yaml`
- `99-worker-set-core-passwd.yaml`
- `99-worker-set-root-passwd.yaml`
- `99-worker-ssh-enable-password-login.yaml`
- `99-worker-thp.yaml`
- `99-worker-timezone.yaml`

#### helper
- `make-registry-mc.sh`

### Typical use

개별 적용:

```bash
oc apply -f mc_init/<file>.yaml
```

전체 적용:

```bash
oc apply -f mc_init/
```

registry MC 생성:

```bash
bash mc_init/make-registry-mc.sh
```

변수 지정 예시:

```bash
HOST=bastion CLUSTER=ocp DOMAIN=example.com OUTDIR=./out bash mc_init/make-registry-mc.sh
```

---

## 4. install/01-pre

배스천 또는 설치 준비 단계에서 사용하는 스크립트입니다.

### `00-make-certs.sh`
사설 인증서 생성 및 로컬 trust anchor 반영.

주요 기능:
- `HOST`, `CLUSTER`, `DOMAIN` 기반 인증서 생성
- SAN 반영
- `/etc/pki/ca-trust/source/anchors` 배포
- `update-ca-trust extract` 실행

### `01-registry.sh`
사설 registry 컨테이너 구성.

주요 기능:
- registry tar 로드
- 다중 registry 컨테이너 실행
- cert/key 배포
- podman systemd unit 생성
- health check 수행

기본 registry 정의:
- `infra_registry` → `5000`
- `cnf_registry` → `5001`

### `02-openshift-admin-user.sh`
htpasswd 기반 OpenShift admin 사용자 생성.

주요 기능:
- htpasswd 파일 생성
- secret 생성/갱신
- OAuth identity provider 반영
- `cluster-admin` 권한 부여

### `03-bastion-account.sh`
배스천 계정 및 로그인 편의 설정.

주요 기능:
- root 비밀번호 설정
- root SSH 로그인 비활성화
- 추가 사용자 생성
- sudoers NOPASSWD 설정
- `/usr/local/bin` PATH 반영
- bastion 호스트에서만 동작하는 `oc login` 자동화 블록 추가

### `04-command-extract.sh`
설치 tarball에서 주요 바이너리 추출.

대상:
- `helm`
- `oc`
- `kubectl`
- `openshift-install`

설치 위치:
- `/usr/local/bin`

### `05-bastion-chrony.sh`
배스천 chrony 설정.

주요 기능:
- chrony.conf 백업
- 지정 NTP 서버/allow 대역 반영
- 설정 검증
- 서비스 재시작
- `chronyc sources`, `chronyc tracking` 확인

---

## 5. install/02-okd-install

### `install/02-okd-install/script.sh`

OKD UPI 성격의 배스천 구성 및 설치 작업을 한 스크립트에 모아둔 파일입니다.

포함 기능 범위:

- `/etc/hosts` 생성
- local repo 설정
- ISO mount 설정
- 필수 패키지 설치
- daemon enable/disable 정리
- SELinux / firewalld 조정
- DNS(named) 구성
- HAProxy 구성
- TFTP 구성
- PXE BIOS/UEFI grub/pxelinux menu 생성
- VLAN 기반 PXE 옵션 구성
- DHCP 구성
- keepalived 구성
- wildcard 인증서 생성
- 로컬 registry 구성
- `oc`, `openshift-install` 추출
- SSH key 생성
- `install-config.yaml` 생성
- pull-secret 파일 생성
- manifest / ignition 생성
- ignition HTTP 배포
- kubeconfig 복사
- oc bash completion 설정

### Notes

이 스크립트는 현재도 하드코딩 값이 적지 않습니다.

예:
- `HOST='bastion'`
- `CLUSTER='lgu'`
- `DOMAIN='okd'`
- PXE / bastion / VIP 대역
- CoreOS 이미지 파일명
- 인터페이스명 (`ens3`, `ens3.300`, `bond0.300`)
- registry/pull-secret 관련 값

따라서 범용 설치 프레임워크라기보다 특정 환경용 설치 자동화 스크립트에 가깝습니다.

---

## 6. install/03-post

설치 완료 후 공통 후처리 스크립트입니다.

### `06-ingress-master.sh`
IngressController를 master 노드에 배치.

주요 기능:
- replica 수 조정
- master nodeSelector 적용
- master toleration 적용

### `07-whereabouts-reconciler.sh`
whereabouts reconciler ConfigMap 및 additionalNetwork 추가.

주요 기능:
- `whereabouts-config` ConfigMap 생성/갱신
- `networks.operator.openshift.io/cluster`에 `additionalNetworks` 추가

### `08-userWorkloadMonitoring.sh`
user workload monitoring 활성화 및 관련 컴포넌트 master 배치 설정.

주요 기능:
- `cluster-monitoring-config`에 `enableUserWorkload: true`
- `user-workload-monitoring-config` 생성/갱신
- Prometheus/Operator/ThanosRuler nodeSelector/toleration 설정

### `09-routingViaHost.sh`
OVN-Kubernetes gateway 설정 패치.

주요 기능:
- `routingViaHost` 반영
- `ipForwarding` 반영

### `10-enableCatalogSources.sh`
OperatorHub default source enable/disable 제어.

주요 기능:
- `disableAllDefaultSources` 설정
- `redhat-operators`
- `community-operators`
- `certified-operators`
- `redhat-marketplace`

enable/disable 값 제어

---

## Requirements

### Common
- bash

### backup
- oc
- jq

### image
- podman
- skopeo

### mc_init
- oc
- MachineConfig 적용 권한

### install/01-pre
- root 권한
- podman / systemctl / openssl / update-ca-trust / chrony 계열 명령
- 일부 스크립트는 OpenShift 로그인 상태 필요

### install/02-okd-install
- root 권한
- RHEL 계열 환경
- DNS/HAProxy/TFTP/DHCP/HTTP/keepalived/podman 설치 가능 환경
- PXE 및 로컬 registry 구성 가능한 네트워크 환경
- `hosts.txt`, `mc/*.yaml`, 설치 tarball, CoreOS 이미지 등 외부 입력 파일 필요

### install/03-post
- oc 로그인 상태
- cluster-admin 수준 권한 권장

---

## Recommended flow

예시 흐름:

1. `install/01-pre/00-make-certs.sh`
2. `install/01-pre/01-registry.sh`
3. `install/01-pre/04-command-extract.sh`
4. 필요 시 `mc_init/` 리소스 준비
5. `install/02-okd-install/script.sh` 기반 배스천/설치 구성
6. 클러스터 설치 완료 후 `install/03-post/` 순차 적용

---

## Caution

- 일부 스크립트에는 기본 계정/비밀번호가 하드코딩되어 있습니다.
- 일부 스크립트는 특정 도메인, 인터페이스명, 네트워크 대역을 전제로 합니다.
- 운영 반영 전 환경 변수화 및 민감정보 분리를 먼저 하는 것이 좋습니다.
- `install/02-okd-install/script.sh`는 범용화 전 검토가 필요합니다.
