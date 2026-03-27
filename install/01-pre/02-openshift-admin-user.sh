#!/usr/bin/env bash
set -euo pipefail

# ===== 변수 =====
USER_NAME="admin"
USER_PASSWORD="telco1234"
HTPASSWD_FILE="./htpasswd"
SECRET_NAME="htpasswd-secret"
OAUTH_NAME="cluster"

# ===== 사전 체크 =====
command -v oc >/dev/null || { echo "oc CLI not found"; exit 1; }
command -v htpasswd >/dev/null || { echo "htpasswd not found (install httpd-tools)"; exit 1; }

echo "[1/6] htpasswd 파일 생성 또는 갱신"
htpasswd -bBc "${HTPASSWD_FILE}" "${USER_NAME}" "${USER_PASSWORD}"

echo "[2/6] OpenShift secret 생성/갱신"
oc create secret generic "${SECRET_NAME}" \
	  --from-file=htpasswd="${HTPASSWD_FILE}" \
	    -n openshift-config \
	      --dry-run=client -o yaml | oc apply -f -

echo "[3/6] OAuth 설정에 htpasswd provider 반영"
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: ${OAUTH_NAME}
spec:
  identityProviders:
  - name: htpasswd
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: ${SECRET_NAME}
EOF

echo "[4/6] OAuth 적용 대기"
sleep 10

echo "[5/6] cluster-admin 권한 부여"
oc adm policy add-cluster-role-to-user cluster-admin "${USER_NAME}"

echo "[6/6] 완료"
echo "User: ${USER_NAME}"
echo "Password: ${USER_PASSWORD}"

