#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/network.env"
load_env_file "${INSTALL_DIR}/00-vars/registry.env"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

MC_INIT_ENABLE="${MC_INIT_ENABLE:-no}"
MC_INIT_COPY_TO_MANIFESTS="${MC_INIT_COPY_TO_MANIFESTS:-no}"

MC_ENABLE_CHRONY="${MC_ENABLE_CHRONY:-yes}"
MC_ENABLE_REGISTRIES="${MC_ENABLE_REGISTRIES:-yes}"
MC_ENABLE_CORE_PASSWORD="${MC_ENABLE_CORE_PASSWORD:-yes}"
MC_ENABLE_ROOT_PASSWORD="${MC_ENABLE_ROOT_PASSWORD:-yes}"
MC_ENABLE_THP="${MC_ENABLE_THP:-no}"

MC_CORE_PASSWORD="${MC_CORE_PASSWORD:-growin}"
MC_ROOT_PASSWORD="${MC_ROOT_PASSWORD:-growin}"

MC_THP_ISOLCPUS="${MC_THP_ISOLCPUS:-}"
MC_THP_HUGEPAGESZ="${MC_THP_HUGEPAGESZ:-1G}"
MC_THP_HUGEPAGES="${MC_THP_HUGEPAGES:-0}"
MC_THP_DISABLE_TRANSPARENT_HUGEPAGE="${MC_THP_DISABLE_TRANSPARENT_HUGEPAGE:-no}"

MC_INIT_RENDER_DIR="${MC_INIT_RENDER_DIR:-${INSTALL_WORKDIR}/mc_init_rendered}"
MC_INIT_MANIFESTS_TARGET_DIR="${MC_INIT_MANIFESTS_TARGET_DIR:-${INSTALL_WORKDIR}/openshift}"

get_bastion_count() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    $2 == "bastion" { count++ }
    END { print count+0 }
  ' "${INSTALL_DIR}/00-inventory/hosts.txt"
}

get_effective_chrony_server_ip() {
  local bastion_count
  bastion_count="$(get_bastion_count)"

  if [[ "${bastion_count}" -lt 2 ]]; then
    echo "${PXE_BASTION_IP}"
  else
    echo "${SERVICE_VIP}"
  fi
}

hash_password() {
  local plain="$1"
  openssl passwd -6 "${plain}"
}

b64_noline() {
  base64 -w 0
}


render_master_chrony() {
	  local server_ip="$1"
	    local out="$2"

	      cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-chrony
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            source: data:text/plain;charset=utf-8;base64,$(cat <<EOC | b64_noline
server ${server_ip}
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOC
)
          mode: 420
          overwrite: true
          path: /etc/chrony.conf
EOF
}

render_worker_chrony() {
	  local server_ip="$1"
	    local out="$2"

	      cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-chrony
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            source: data:text/plain;charset=utf-8;base64,$(cat <<EOC | b64_noline
server ${server_ip}
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOC
)
          mode: 420
          overwrite: true
          path: /etc/chrony.conf
EOF
}

render_master_registries() {
  local out="$1"
  local reg_host="${HOST}.${CLUSTER_NAME}.${BASE_DOMAIN}"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-registries
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/containers/registries.conf.d/growin.registry.conf
        mode: 0644
        overwrite: true
        contents:
          source: data:text/plain;charset=utf-8;base64,$(cat <<EOC | b64_noline
[[registry]]
  prefix = ""
  location = "registry.access.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.access.redhat.com"

[[registry]]
  prefix = ""
  location = "registry.redhat.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.redhat.io"

[[registry]]
  prefix = ""
  location = "docker.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/docker.io"

[[registry]]
  prefix = ""
  location = "docker.elastic.co"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/docker.elastic.co"

[[registry]]
  prefix = ""
  location = "gcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/gcr.io"

[[registry]]
  prefix = ""
  location = "quay.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/quay.io"

[[registry]]
  prefix = ""
  location = "registry.k8s.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.k8s.io"

[[registry]]
  prefix = ""
  location = "redhat-operator-index"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/redhat-operator-index"

[[registry]]
  prefix = ""
  location = "ghcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/ghcr.io"

[[registry]]
  prefix = ""
  location = "registry.connect.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.connect.redhat.com"
EOC
)
EOF
}

render_worker_registries() {
  local out="$1"
  local reg_host="${HOST}.${CLUSTER_NAME}.${BASE_DOMAIN}"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-registries
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/containers/registries.conf.d/growin.registry.conf
        mode: 0644
        overwrite: true
        contents:
          source: data:text/plain;charset=utf-8;base64,$(cat <<EOC | b64_noline
[[registry]]
  prefix = ""
  location = "registry.access.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.access.redhat.com"

[[registry]]
  prefix = ""
  location = "registry.redhat.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.redhat.io"

[[registry]]
  prefix = ""
  location = "docker.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/docker.io"

[[registry]]
  prefix = ""
  location = "docker.elastic.co"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/docker.elastic.co"

[[registry]]
  prefix = ""
  location = "gcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/gcr.io"

[[registry]]
  prefix = ""
  location = "quay.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/quay.io"

[[registry]]
  prefix = ""
  location = "registry.k8s.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.k8s.io"

[[registry]]
  prefix = ""
  location = "redhat-operator-index"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/redhat-operator-index"

[[registry]]
  prefix = ""
  location = "ghcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/ghcr.io"

[[registry]]
  prefix = ""
  location = "registry.connect.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${reg_host}:5000/registry.connect.redhat.com"
EOC
)
EOF
}

render_master_core_password() {
  local out="$1"
  local hashed
  hashed="$(hash_password "${MC_CORE_PASSWORD}")"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-set-core-passwd
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(printf 'core:%s\n' "${hashed}" | b64_noline)
        mode: 420
        overwrite: true
        path: /etc/core.passwd
    systemd:
      units:
      - name: set-core-passwd.service
        enabled: true
        contents: |
          [Unit]
          Description=Set 'core' user password for out-of-band login
          [Service]
          Type=oneshot
          ExecStart=/bin/sh -c 'chpasswd -e < /etc/core.passwd'
          [Install]
          WantedBy=multi-user.target
EOF
}

render_worker_core_password() {
  local out="$1"
  local hashed
  hashed="$(hash_password "${MC_CORE_PASSWORD}")"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-set-core-passwd
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(printf 'core:%s\n' "${hashed}" | b64_noline)
        mode: 420
        overwrite: true
        path: /etc/core.passwd
    systemd:
      units:
      - name: set-core-passwd.service
        enabled: true
        contents: |
          [Unit]
          Description=Set 'core' user password for out-of-band login
          [Service]
          Type=oneshot
          ExecStart=/bin/sh -c 'chpasswd -e < /etc/core.passwd'
          [Install]
          WantedBy=multi-user.target
EOF
}

render_master_root_password() {
  local out="$1"
  local hashed
  hashed="$(hash_password "${MC_ROOT_PASSWORD}")"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-set-root-passwd
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(printf 'root:%s\n' "${hashed}" | b64_noline)
        mode: 420
        overwrite: true
        path: /etc/root.passwd
    systemd:
      units:
      - name: set-root-passwd.service
        enabled: true
        contents: |
          [Unit]
          Description=Set 'root' user password for out-of-band login
          [Service]
          Type=oneshot
          ExecStart=/bin/sh -c 'chpasswd -e < /etc/root.passwd'
          [Install]
          WantedBy=multi-user.target
EOF
}

render_worker_root_password() {
  local out="$1"
  local hashed
  hashed="$(hash_password "${MC_ROOT_PASSWORD}")"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-set-root-passwd
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(printf 'root:%s\n' "${hashed}" | b64_noline)
        mode: 420
        overwrite: true
        path: /etc/root.passwd
    systemd:
      units:
      - name: set-root-passwd.service
        enabled: true
        contents: |
          [Unit]
          Description=Set 'root' user password for out-of-band login
          [Service]
          Type=oneshot
          ExecStart=/bin/sh -c 'chpasswd -e < /etc/root.passwd'
          [Install]
          WantedBy=multi-user.target
EOF
}

render_worker_thp() {
  local out="$1"
  local kargs=""

  [[ -n "${MC_THP_ISOLCPUS}" ]] && kargs+=" isolcpus=${MC_THP_ISOLCPUS}"
  [[ -n "${MC_THP_HUGEPAGESZ}" ]] && kargs+=" hugepagesz=${MC_THP_HUGEPAGESZ}"
  [[ -n "${MC_THP_HUGEPAGES}" ]] && kargs+=" hugepages=${MC_THP_HUGEPAGES}"
  [[ "${MC_THP_DISABLE_TRANSPARENT_HUGEPAGE}" == "yes" ]] && kargs+=" transparent_hugepage=never"

  kargs="${kargs# }"

  cat > "${out}" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-thp
spec:
  kernelArguments:
  - ${kargs}
EOF
}

copy_to_manifests_if_enabled() {
  if [[ "${MC_INIT_COPY_TO_MANIFESTS}" == "yes" ]]; then
    find "${MC_INIT_RENDER_DIR}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -exec cp -f {} "${MC_INIT_MANIFESTS_TARGET_DIR}/" \;
    log "copied rendered mc files to ${MC_INIT_MANIFESTS_TARGET_DIR}"
  else
    log "MC_INIT_COPY_TO_MANIFESTS=${MC_INIT_COPY_TO_MANIFESTS}, skip copy to manifests"
  fi
}

main() {
  require_root
  require_cmd openssl
  require_cmd base64

  if [[ "${MC_INIT_ENABLE}" != "yes" ]]; then
    log "MC_INIT_ENABLE=${MC_INIT_ENABLE}, skipping mc_init render"
    exit 0
  fi

  [[ -d "${INSTALL_WORKDIR}" ]] || die "install workdir not found: ${INSTALL_WORKDIR}"
  [[ -d "${MC_INIT_MANIFESTS_TARGET_DIR}" ]] || die "openshift manifests target dir not found: ${MC_INIT_MANIFESTS_TARGET_DIR}"

  ensure_dir "${MC_INIT_RENDER_DIR}"

  local chrony_ip
  chrony_ip="$(get_effective_chrony_server_ip)"

  if [[ "${MC_ENABLE_CHRONY}" == "yes" ]]; then
    render_master_chrony "${chrony_ip}" "${MC_INIT_RENDER_DIR}/99-master-chrony.yaml"
    render_worker_chrony "${chrony_ip}" "${MC_INIT_RENDER_DIR}/99-worker-chrony.yaml"
  fi

  if [[ "${MC_ENABLE_REGISTRIES}" == "yes" ]]; then
    render_master_registries "${MC_INIT_RENDER_DIR}/99-master-registries.yaml"
    render_worker_registries "${MC_INIT_RENDER_DIR}/99-worker-registries.yaml"
  fi

  if [[ "${MC_ENABLE_CORE_PASSWORD}" == "yes" ]]; then
    render_master_core_password "${MC_INIT_RENDER_DIR}/99-master-set-core-passwd.yaml"
    render_worker_core_password "${MC_INIT_RENDER_DIR}/99-worker-set-core-passwd.yaml"
  fi

  if [[ "${MC_ENABLE_ROOT_PASSWORD}" == "yes" ]]; then
    render_master_root_password "${MC_INIT_RENDER_DIR}/99-master-set-root-passwd.yaml"
    render_worker_root_password "${MC_INIT_RENDER_DIR}/99-worker-set-root-passwd.yaml"
  fi

  if [[ "${MC_ENABLE_THP}" == "yes" ]]; then
    render_worker_thp "${MC_INIT_RENDER_DIR}/99-worker-thp.yaml"
  fi

  copy_to_manifests_if_enabled

  log "mc_init rendered files:"
  ls -l "${MC_INIT_RENDER_DIR}"
}

main "$@"
