# ocp-tools

OpenShift 운영 작업에 사용하는 스크립트 모음입니다.

현재 레포에는 클러스터 리소스 백업 스크립트, 이미지 미러링 스크립트, MachineConfig 초기 설정 리소스가 포함되어 있습니다.

---

## Table of Contents

- [Repository Structure](#repository-structure)
- [Scripts](#scripts)
  - [1) backup/growin_ocp_backup.sh](#1-backupgrowin_ocp_backupsh)
  - [2) backup/growin_ocp_backup_v0.2.sh](#2-backupgrowin_ocp_backup_v02sh)
  - [3) image/mirror-images.sh](#3-imagemirror-imagessh)
  - [4) mc_init](#4-mc_init)
- [Requirements](#requirements)

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
└── mc_init/
    ├── 99-master-chrony.yaml
    ├── 99-master-iscsi-scan-add.yaml
    ├── 99-master-multipath.yaml
    ├── 99-master-registries.yaml
    ├── 99-master-set-core-passwd.yaml
    ├── 99-master-set-root-passwd.yaml
    ├── 99-master-ssh-enable-password-login.yaml
    ├── 99-master-timezone.yaml
    ├── 99-worker-chrony.yaml
    ├── 99-worker-iommu.yaml
    ├── 99-worker-iscsi-scan-add.yaml
    ├── 99-worker-multipath.yaml
    ├── 99-worker-registries.yaml
    ├── 99-worker-set-core-passwd.yaml
    ├── 99-worker-set-root-passwd.yaml
    ├── 99-worker-ssh-enable-password-login.yaml
    ├── 99-worker-thp.yaml
    ├── 99-worker-timezone.yaml
    └── make-registry-mc.sh
```

---

## Scripts

### 1) backup/growin_ocp_backup.sh

기존 OpenShift 정보 백업 스크립트입니다.

Primary Function:

- 클러스터 전반 리소스 목록 수집
- Pod, Service, StatefulSet, Deployment, DeploymentConfig, DaemonSet 개별 YAML 백업
- PV, PVC, Node, CO, MC, MCP, VM, SC, KubeletConfig, NAD, CSV, ConfigMap 수집
- `oc get ... -o wide` 스냅샷 파일 생성
- 마스터 노드에 SSH 접속하여 `cluster-backup.sh` 실행

Features:

- 순차 처리 방식
- 리소스별 반복 `oc get` 호출
- PVC는 `describe` 결과로 저장
- CSV는 이름 기준 중복 제거 후 저장

How to Use:

```bash
bash backup/growin_ocp_backup.sh
```

---

### 2) backup/growin_ocp_backup_v0.2.sh

병렬 처리 기반으로 개선된 백업 스크립트입니다.

Primary Function:

- Namespace 단위 병렬 백업
- 리소스 JSON 수집 후 개별 파일 저장
- CSV 이름 기준 dedup
- cluster-scope 리소스 JSON 백업
- warn / err 로그 분리

Features:

- 병렬 처리 (기본 12)
- API 호출 최소화
- jq / flock 사용
- optional resource 자동 판단

How to Use:

```bash
bash backup/growin_ocp_backup_v0.2.sh
```

```bash
PARALLEL_NS=20 bash backup/growin_ocp_backup_v0.2.sh
```

---

### 3) image/mirror-images.sh

이미지 목록을 읽어 대상 레지스트리로 병렬 미러링하는 스크립트입니다.

Primary Function:

- 이미지 추출 및 중복 제거
- 필요한 레지스트리 자동 로그인
- 대상 레지스트리에 이미지가 이미 존재하면 skip
- `skopeo copy --all` 기반 복사

Features:

- 병렬 처리
- retry 지원
- success / fail 로그 분리
- 대상 레지스트리 및 작업 수 인자화

How to Use:

```bash
bash image/mirror-images.sh images.txt bastion.ocp.lsh:5000 6 2 ./mirror-logs
```

---

### 4) mc_init

OpenShift 노드 초기 설정용 MachineConfig 리소스와 생성 스크립트 모음입니다.

Primary Function:

- master / worker 노드 공통 초기 설정
- chrony 설정 배포
- multipath 설정 배포
- iscsiadm 자동 로그인 systemd unit 추가
- core / root 계정 비밀번호 설정
- SSH password login 허용
- timezone 설정
- worker 노드 kernel argument 설정
- registry mirror MachineConfig 생성 및 배포

Included Files:

#### master
- `99-master-chrony.yaml` : master 노드 chrony 설정
- `99-master-iscsi-scan-add.yaml` : master 노드 iscsiadm 로그인 유닛 추가
- `99-master-multipath.yaml` : master 노드 multipath.conf 배포
- `99-master-registries.yaml` : master 노드 registries mirror 설정
- `99-master-set-core-passwd.yaml` : master 노드 core 비밀번호 설정
- `99-master-set-root-passwd.yaml` : master 노드 root 비밀번호 설정
- `99-master-ssh-enable-password-login.yaml` : master 노드 SSH password login 허용
- `99-master-timezone.yaml` : master 노드 timezone 설정

#### worker
- `99-worker-chrony.yaml` : worker 노드 chrony 설정
- `99-worker-iommu.yaml` : worker 노드 IOMMU kernel argument 설정
- `99-worker-iscsi-scan-add.yaml` : worker 노드 iscsiadm 로그인 유닛 추가
- `99-worker-multipath.yaml` : worker 노드 multipath.conf 배포
- `99-worker-registries.yaml` : worker 노드 registries mirror 설정
- `99-worker-set-core-passwd.yaml` : worker 노드 core 비밀번호 설정
- `99-worker-set-root-passwd.yaml` : worker 노드 root 비밀번호 설정
- `99-worker-ssh-enable-password-login.yaml` : worker 노드 SSH password login 허용
- `99-worker-thp.yaml` : worker 노드 CPU isolation / hugepage / THP 관련 kernel argument 설정
- `99-worker-timezone.yaml` : worker 노드 timezone 설정

#### helper script
- `make-registry-mc.sh` : registry mirror MachineConfig YAML 자동 생성 스크립트

How to Use:

개별 MachineConfig 적용:

```bash
oc apply -f mc_init/<file>.yaml
```

디렉토리 전체 적용:

```bash
oc apply -f mc_init/
```

registry MachineConfig 생성 스크립트 사용:

```bash
bash mc_init/make-registry-mc.sh
```

변수 지정 예시:

```bash
HOST=bastion CLUSTER=ocp DOMAIN=example.com OUTDIR=./out bash mc_init/make-registry-mc.sh
```

---

## Requirements

backup:

- oc
- jq
- flock

image:

- podman
- skopeo

mc_init:

- oc
- OpenShift MachineConfig 적용 권한
