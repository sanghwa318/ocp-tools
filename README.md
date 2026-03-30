# ocp-tools

OpenShift / OKD cluster bootstrap automation toolkit.

This repository provides a stage-based installation pipeline for bare-metal or UPI-style environments using PXE, local registry, and bastion-based control.

---

## Overview

The installation flow is divided into 3 explicit stages:

```text
pre     → bastion / infra setup
install → cluster creation
post    → cluster configuration
```

Each stage is executed independently via `install/run.sh`.

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
├── install/
│   ├── 00-inventory/
│   │   └── hosts.txt
│   ├── 00-vars/
│   │   ├── bastion.env
│   │   ├── cluster.env
│   │   ├── install-config.env
│   │   ├── network.env
│   │   ├── post.env
│   │   └── registry.env
│   ├── 01-pre/
│   │   ├── 00-command-extract.sh
│   │   ├── 01-disable-selinux.sh
│   │   ├── 02-bastion-account.sh
│   │   ├── 03-bastion-chrony.sh
│   │   ├── 04-make-certs.sh
│   │   ├── 05-registry.sh
│   │   ├── 06-hosts-render.sh
│   │   ├── 07-dns-render.sh
│   │   ├── 08-haproxy-render.sh
│   │   ├── 09-tftp-install.sh
│   │   ├── 10-dhcp-render.sh
│   │   ├── 11-pxe-grub-render.sh
│   │   └── 12-keepalived-render.sh
│   ├── 02-install/
│   │   ├── 00-install-config-render.sh
│   │   ├── 01-manifests-generate.sh
│   │   ├── 02-ignition-generate.sh
│   │   ├── 03-publish-artifacts.sh
│   │   └── 04-create-cluster.sh
│   ├── 03-post/
│   │   ├── 00-openshift-admin-user.sh
│   │   ├── 01-ingress-master.sh
│   │   ├── 02-whereabouts-reconciler.sh
│   │   ├── 03-userWorkloadMonitoring.sh
│   │   ├── 04-routingViaHost.sh
│   │   └── 05-enableCatalogSources.sh
│   ├── lib/
│   │   └── common.sh
│   ├── templates/
│   │   ├── dhcpd.conf.tmpl
│   │   ├── haproxy.cfg.tmpl
│   │   ├── install-config.yaml.tmpl
│   │   ├── keepalived.conf.tmpl
│   │   ├── named.conf.tmpl
│   │   └── zone.forward.tmpl
│   └── run.sh
└── mc_init/
```

---

## Stage Execution

### PRE

```bash
cd install
bash run.sh pre
```

What it does:

- Extract required commands
- Disable SELinux
- Configure bastion account
- Configure chrony
- Generate certificates
- Start local registry
- Configure `/etc/hosts`
- Configure DNS
- Configure HAProxy
- Configure TFTP
- Configure DHCP
- Generate PXE / GRUB configs
- Configure keepalived

### INSTALL

```bash
cd install
bash run.sh install
```

What it does:

- Render `install-config.yaml`
- Generate manifests
- Generate ignition configs
- Publish FCOS artifacts and ignition files
- Run cluster creation / bootstrap wait flow

### POST

```bash
cd install
bash run.sh post
```

What it does:

- Create OpenShift admin user
- Configure ingress scheduling
- Enable whereabouts reconciler
- Enable user workload monitoring
- Apply routingViaHost
- Enable catalog sources

---

## Inventory Format

`install/00-inventory/hosts.txt`

```text
hostname role ip gateway nic mac nettype vlan_id install_dev
```

Example:

```text
bastion1 bastion 192.168.200.10 192.168.200.1 ens3 52:54:00:aa:bb:01 ethernet - /dev/vda
bastion2 bastion 192.168.200.11 192.168.200.1 ens3 52:54:00:aa:bb:02 ethernet - /dev/vda
bootstrap bootstrap 192.168.200.41 192.168.200.1 ens3 52:54:00:aa:bb:41 ethernet - /dev/vda
master1 master 192.168.200.21 192.168.200.1 ens3 52:54:00:aa:bb:21 vlan 300 /dev/vda
worker1 worker 192.168.200.31 192.168.200.1 ens3,ens4 52:54:00:aa:bb:31 bond - /dev/sda
```

Notes:

- `nettype` supports `ethernet`, `vlan`, `bond`
- worker bond interface is rendered as `bond0`
- bootstrap/master default install device is `/dev/vda`
- worker default install device is `/dev/sda`

---

## Environment Variables

Configuration files are stored under:

```text
install/00-vars/
```

Main files:

| file | purpose |
|------|---------|
| `cluster.env` | cluster identity and naming |
| `network.env` | PXE / VIP / DHCP / DNS / network values |
| `registry.env` | local registry settings |
| `bastion.env` | bastion user / shell settings |
| `install-config.env` | install-config and install flow settings |
| `post.env` | post-install cluster configuration |

---

## PXE / Bootstrap Design

### Addressing policy

- API / DNS / NTP use VIP
- HTTP / TFTP / PXE source uses bastion1 real IP

### Boot protocol policy

- PXELINUX kernel/initramfs → TFTP
- GRUB kernel/initramfs → relative filename
- rootfs → HTTP
- ignition → HTTP

### Generated config naming

Per-MAC files are generated as:

```text
pxelinux.cfg/01-xx-xx-xx-xx-xx-xx
grub.cfg-01-xx-xx-xx-xx-xx-xx
```

MAC addresses are normalized to lowercase and `:` is converted to `-`.

---

## install-config.yaml Policy

The install-config is generated from `install/templates/install-config.yaml.tmpl`.

Current design:

- `platform: none`
- `networkType: OVNKubernetes`
- explicit `additionalTrustBundle`
- explicit `imageContentSources`
- no `apiVIPs`
- no `ingressVIPs`

`install-config.yaml` is always backed up before regeneration.

---

## DNS Policy

- Forward zone only
- Reverse zone is not used
- `named.conf` is fully managed by the script for this install environment

---

## HAProxy Policy

- API / MCS backends → master nodes
- Ingress backends → worker / infra nodes

---

## keepalived Policy

- keepalived runs only on bastion nodes
- bastion HA is inventory-based
- notify script is intentionally not used

---

## Requirements

- root access
- RHEL-like bastion host
- `openshift-install`
- `oc`
- SSH public key
- pull secret
- additional trust bundle file
- FCOS kernel / initramfs / rootfs artifacts
- working PXE / HTTP / registry environment

---

## Usage Example

```bash
cd install

# 1. prepare variables and inventory
vi 00-vars/*.env
vi 00-inventory/hosts.txt

# 2. bastion / infra setup
bash run.sh pre

# 3. cluster creation
bash run.sh install

# 4. login with kubeconfig after cluster is reachable
export KUBECONFIG=/root/openshift-install/auth/kubeconfig
oc login ...

# 5. cluster post configuration
bash run.sh post
```

---

## Other Directories

### `backup/`

Cluster resource backup scripts.

- `growin_ocp_backup.sh`
- `growin_ocp_backup_v0.2.sh`

### `image/`

Parallel image mirroring script.

- `mirror-images.sh`

### `mc_init/`

MachineConfig-based node initialization resources and helpers.

---

## Notes

- `run.sh` intentionally supports only `pre`, `install`, `post`
- `all` mode is intentionally not used
- post stage must be executed only after cluster API is reachable
- TFTP setup is required before DHCP / PXE flow
- publish step must complete before nodes attempt bootstrap

---

## TODO

- registry mirror validation
- additional precheck script
- install/post health verification
- README expansion with network diagrams
