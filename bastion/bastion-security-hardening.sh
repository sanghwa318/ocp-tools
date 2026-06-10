#!/bin/bash
# =============================================================================
# bastion_security_hardening.sh
# Bastion 서버 보안 강화 자동화 스크립트
# =============================================================================

set -e

LOGFILE="/var/log/security_hardening_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

log() { echo "[$(date '+%F %T')] [INFO]  $*"; }
ok()  { echo "[$(date '+%F %T')] [OK]    $*"; }
err() { echo "[$(date '+%F %T')] [ERROR] $*"; }

backup() {
    local f="$1"
    if [ -f "$f" ] && [ ! -f "${f}.bak" ]; then
        cp -p "$f" "${f}.bak"
        log "백업 완료: ${f}.bak"
    fi
}

log "========== 보안 강화 스크립트 시작 =========="

# =============================================================================
# 1. 비밀번호 복잡성 설정
# /etc/security/pwquality.conf
# =============================================================================
log "[1] 비밀번호 복잡성 설정"

backup /etc/security/pwquality.conf

declare -A PWQUALITY=(
    [minlen]=8
    [dcredit]=-1
    [ucredit]=-1
    [lcredit]=-1
    [ocredit]=-1
)

for key in "${!PWQUALITY[@]}"; do
    val="${PWQUALITY[$key]}"
    if grep -qE "^#?\s*${key}\s*=" /etc/security/pwquality.conf; then
        sed -i "s|^#\?\s*${key}\s*=.*|${key} = ${val}|" /etc/security/pwquality.conf
    else
        echo "${key} = ${val}" >> /etc/security/pwquality.conf
    fi
done
ok "pwquality.conf 설정 완료"

# =============================================================================
# 2. 패스워드 최대/최소 사용 기간 설정
# /etc/login.defs + chage
# =============================================================================
log "[2] 패스워드 최대/최소 사용 기간 설정"

backup /etc/login.defs

sed -i "s|^PASS_MAX_DAYS.*|PASS_MAX_DAYS   90|" /etc/login.defs
sed -i "s|^PASS_MIN_DAYS.*|PASS_MIN_DAYS   1|"  /etc/login.defs

chage -M 90 root
chage -m 1  root

ok "login.defs 및 root chage 설정 완료"

# =============================================================================
# 3. 패스워드 이력 기억 설정
# /etc/security/pwhistory.conf
# =============================================================================
log "[3] 패스워드 이력 기억 설정"

backup /etc/security/pwhistory.conf

cat > /etc/security/pwhistory.conf << 'EOF'
enforce_for_root
remember = 4
file = /etc/security/opasswd
EOF

[ -f /etc/security/opasswd ] || touch /etc/security/opasswd
chmod 600 /etc/security/opasswd

ok "pwhistory.conf 설정 완료"

# =============================================================================
# 4. 계정 잠금 임계값 및 PAM 설정
# /etc/pam.d/password-auth  : pam_pwhistory.so required remember=5
# /etc/pam.d/system-auth    : pam_unix.so sufficient remember=5 (두 줄)
# - faillock: deny=5, unlock_time=600
# =============================================================================
log "[4] PAM 계정 잠금 및 패스워드 이력 설정"

# -- password-auth --
backup /etc/pam.d/password-auth
cat > /etc/pam.d/password-auth << 'EOF'
auth        required      pam_env.so
auth        required      pam_faillock.so preauth silent audit deny=5 unlock_time=600
auth        sufficient    pam_unix.so try_first_pass nullok
auth        [default=die] pam_faillock.so authfail audit deny=5 unlock_time=600
auth        required      pam_deny.so

account     required      pam_faillock.so
account     required      pam_unix.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    required      pam_pwhistory.so remember=5
password    sufficient    pam_unix.so try_first_pass use_authtok nullok sha512 shadow
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session    optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOF
ok "/etc/pam.d/password-auth 설정 완료"

# -- system-auth --
backup /etc/pam.d/system-auth
cat > /etc/pam.d/system-auth << 'EOF'
auth        required      pam_env.so
auth        required      pam_faillock.so preauth silent audit deny=5 unlock_time=600
auth        sufficient    pam_unix.so try_first_pass nullok
auth        [default=die] pam_faillock.so authfail audit deny=5 unlock_time=600
auth        required      pam_deny.so

account     required      pam_faillock.so
account     required      pam_unix.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so remember=5
password    sufficient    pam_unix.so try_first_pass use_authtok nullok sha512 shadow
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session    optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOF
ok "/etc/pam.d/system-auth 설정 완료"

# =============================================================================
# 5. root 계정 원격 SSH 접속 제한
# /etc/ssh/sshd_config
# =============================================================================
log "[5] SSH 보안 설정"

backup /etc/ssh/sshd_config

set_sshd() {
    local key="$1" val="$2"
    if grep -qE "^#?\s*${key}\s" /etc/ssh/sshd_config; then
        sed -i "s|^#\?\s*${key}\s.*|${key} ${val}|" /etc/ssh/sshd_config
    else
        echo "${key} ${val}" >> /etc/ssh/sshd_config
    fi
}

set_sshd "PermitRootLogin"    "no"
set_sshd "AllowTcpForwarding" "no"

# 허용 알고리즘 설정
CIPHERS="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
KEXALGORITHMS="curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"
MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
ALLOWUSERS="core@100.230.1.* core@172.30.*"

set_sshd "Ciphers"       "$CIPHERS"
set_sshd "KexAlgorithms" "$KEXALGORITHMS"
set_sshd "MACs"          "$MACS"
set_sshd "AllowUsers"    "$ALLOWUSERS"

systemctl restart sshd
ok "sshd_config 설정 완료 및 sshd 재시작"

# =============================================================================
# 6. 원격 터미널 접속 타임아웃 설정 (TMOUT=1800)
#    SHELL History 설정 (HISTSIZE, HISTTIMEFORMAT)
# /etc/profile
# =============================================================================
log "[6] /etc/profile 환경 설정 (TMOUT, HISTSIZE)"

backup /etc/profile

PROFILE_APPEND=""

grep -q "^TMOUT=" /etc/profile || PROFILE_APPEND+="
# 원격 터미널 타임아웃 (30분)
TMOUT=1800
export TMOUT"

grep -q "^HISTSIZE=" /etc/profile || PROFILE_APPEND+="
# Shell History 설정
HISTSIZE=5000
HISTTIMEFORMAT='%F %T   '
export HISTSIZE HISTTIMEFORMAT"

if [ -n "$PROFILE_APPEND" ]; then
    echo "$PROFILE_APPEND" >> /etc/profile
fi
ok "/etc/profile 설정 완료"

# =============================================================================
# 7. UMASK 설정 (022 확인 — 이미 022라면 skip)
# /etc/bashrc
# =============================================================================
log "[7] UMASK 설정 확인"

CURRENT_UMASK=$(grep -oE 'umask\s+[0-9]+' /etc/bashrc | awk '{print $2}' | head -1)
if [ "$CURRENT_UMASK" != "022" ]; then
    backup /etc/bashrc
    sed -i "s|umask\s\+[0-9]\+|umask 022|g" /etc/bashrc
    ok "/etc/bashrc umask 022 로 변경 완료"
else
    ok "umask 이미 022 — 변경 불필요"
fi

# =============================================================================
# 8. 취약 서비스 비활성화 (tftp, tftp.socket)
# =============================================================================
log "[8] 취약 서비스 비활성화 (tftp)"

for SVC in tftp tftp.socket; do
    if systemctl list-unit-files "$SVC" 2>/dev/null | grep -q "$SVC"; then
        systemctl disable "$SVC" 2>/dev/null && ok "$SVC 비활성화 완료" || log "$SVC 이미 비활성화 또는 없음"
        systemctl stop    "$SVC" 2>/dev/null || true
    else
        log "$SVC 유닛 없음 — skip"
    fi
done

# =============================================================================
# 9. DNS 설정 (named.conf)
# - allow-transfer none
# - version none
# - logging 항목 추가
# =============================================================================
log "[9] named.conf 보안 설정"

backup /etc/named.conf

# allow-transfer 설정
if grep -q "allow-transfer" /etc/named.conf; then
    sed -i "s|allow-transfer\s*{[^}]*};|allow-transfer { none; };|g" /etc/named.conf
else
    sed -i "/options\s*{/a\        allow-transfer { none; };" /etc/named.conf
fi

# version 설정
if grep -q "^\s*version" /etc/named.conf; then
    sed -i "s|^\s*version\s*\".*\";|        version none;|" /etc/named.conf
else
    sed -i "/options\s*{/a\        version none;" /etc/named.conf
fi

# logging 블록 내 category 추가 (기존 블록 마지막 }; 앞에 삽입)
if ! grep -q "category xfer-out" /etc/named.conf; then
    sed -i '/^logging\s*{/,/^};/{
        /^};/{
            i\    category xfer-out        { default_debug; };\
    category update          { default_debug; };\
    category update-security { default_debug; };\
    category dnssec          { default_debug; };\
    category security        { null; };
        }
    }' /etc/named.conf
fi

named-checkconf /etc/named.conf && ok "named.conf 문법 검사 통과" || err "named.conf 문법 오류 확인 필요"

# =============================================================================
# 10. Crontab 설정파일 권한
# =============================================================================
log "[10] /etc/cron.deny 권한 설정"

[ -f /etc/cron.deny ] || touch /etc/cron.deny
chmod 640 /etc/cron.deny
ok "/etc/cron.deny chmod 640 완료"

# Cron 사용 계정 제한 (core 계정 추가)
if ! grep -q "^core$" /etc/cron.deny; then
    echo "core" >> /etc/cron.deny
    ok "core 계정 cron.deny 등록 완료"
else
    ok "core 이미 cron.deny에 등록됨"
fi

# =============================================================================
# 11. 주요 파일 권한 설정
# =============================================================================
log "[11] 시스템 주요 파일 권한 설정"

chmod 640 /etc/rsyslog.conf  && ok "/etc/rsyslog.conf chmod 640"
chmod 644 /var/log/lastlog   && ok "/var/log/lastlog chmod 644"

# =============================================================================
# 12. SUID/SGID 제거
# =============================================================================
log "[12] 불필요한 SUID/SGID 제거"

chmod -s /usr/bin/newgrp    && ok "/usr/bin/newgrp SUID 제거"
chmod -s /sbin/unix_chkpwd  && ok "/sbin/unix_chkpwd SGID 제거"

# =============================================================================
# 13. su 명령어 wheel 그룹 제한
# =============================================================================
log "[13] su 명령어 wheel 그룹 제한"

chgrp wheel /usr/bin/su && chmod 4750 /usr/bin/su
[ -f /bin/su ] && chgrp wheel /bin/su && chmod 4750 /bin/su || true
ok "su wheel 그룹 권한 설정 완료"

backup /etc/pam.d/su

# pam_wheel.so use_uid 라인 활성화
if grep -q "#\s*auth\s*required\s*pam_wheel.so use_uid" /etc/pam.d/su; then
    sed -i "s|#\s*auth\s*required\s*pam_wheel.so use_uid|auth\t\trequired\tpam_wheel.so use_uid|" /etc/pam.d/su
elif ! grep -q "pam_wheel.so use_uid" /etc/pam.d/su; then
    sed -i "/pam_rootok.so/a auth\t\trequired\tpam_wheel.so use_uid" /etc/pam.d/su
fi
ok "/etc/pam.d/su pam_wheel 설정 완료"

# =============================================================================
# 14. 시스템 사용 주의사항 배너
# /etc/issue.net, /etc/motd
# =============================================================================
log "[14] 로그인 배너 설정"

echo "WARNING: Authorized use only" | tee /etc/issue.net /etc/motd > /dev/null
ok "/etc/issue.net, /etc/motd 배너 설정 완료"

# sshd_config에 Banner 경로 지정
set_sshd "Banner" "/etc/issue.net"
systemctl restart sshd

# =============================================================================
# 15. Power Key 및 Ctrl+Alt+Del 방지
# /etc/systemd/logind.conf, /etc/systemd/system.conf
# =============================================================================
log "[15] Power Key / Ctrl+Alt+Del 방지 설정"

backup /etc/systemd/logind.conf
backup /etc/systemd/system.conf

# logind.conf: HandlePowerKey=ignore
if grep -q "^#\?HandlePowerKey=" /etc/systemd/logind.conf; then
    sed -i "s|^#\?HandlePowerKey=.*|HandlePowerKey=ignore|" /etc/systemd/logind.conf
else
    echo "HandlePowerKey=ignore" >> /etc/systemd/logind.conf
fi

# system.conf: CtrlAltDelBurstAction=none
if grep -q "^#\?CtrlAltDelBurstAction=" /etc/systemd/system.conf; then
    sed -i "s|^#\?CtrlAltDelBurstAction=.*|CtrlAltDelBurstAction=none|" /etc/systemd/system.conf
else
    echo "CtrlAltDelBurstAction=none" >> /etc/systemd/system.conf
fi

systemctl disable ctrl-alt-del.target 2>/dev/null || true
systemctl mask    ctrl-alt-del.target
ok "Power Key / Ctrl+Alt+Del 방지 설정 완료"

# =============================================================================
# 16. SAR (sysstat) 설정
# /etc/sysconfig/sysstat, sysstat-collect.timer
# =============================================================================
log "[16] sysstat (sar) 설정"

backup /etc/sysconfig/sysstat

if grep -q "^HISTORY=" /etc/sysconfig/sysstat; then
    sed -i "s|^HISTORY=.*|HISTORY=31|" /etc/sysconfig/sysstat
else
    echo "HISTORY=31" >> /etc/sysconfig/sysstat
fi

COLLECT_TIMER="/usr/lib/systemd/system/sysstat-collect.timer"
if [ -f "$COLLECT_TIMER" ]; then
    backup "$COLLECT_TIMER"
    # OnCalendar 1분 주기로 설정
    sed -i "s|^OnUnitActiveSec=.*|OnUnitActiveSec=1m|"  "$COLLECT_TIMER"
    sed -i "s|^AccuracySec=.*|AccuracySec=1s|"          "$COLLECT_TIMER"
    sed -i "s|^OnCalendar=.*|OnCalendar=*:00/1|"        "$COLLECT_TIMER"
    systemctl daemon-reload
    ok "sysstat-collect.timer 1분 주기 설정 완료"
fi

# =============================================================================
# 17. GRUB 커널 파라미터 (algif_aead 블랙리스트)
# =============================================================================
log "[17] GRUB initcall_blacklist 설정"

if ! grep -q "initcall_blacklist=algif_aead_init" /proc/cmdline; then
    grubby --update-kernel=ALL --args="initcall_blacklist=algif_aead_init"
    ok "grubby initcall_blacklist 설정 완료 (재부팅 후 적용)"
else
    ok "initcall_blacklist=algif_aead_init 이미 적용됨"
fi

# =============================================================================
# 완료
# =============================================================================
log "=========================================="
log "보안 강화 스크립트 완료"
log "로그 파일: $LOGFILE"
log ""
log "[주의] 아래 항목은 재부팅 후 적용됩니다:"
log "  - GRUB 커널 파라미터 (initcall_blacklist)"
log "  - /etc/profile (TMOUT, HISTSIZE) — 새 세션부터 적용"
log "=========================================="
