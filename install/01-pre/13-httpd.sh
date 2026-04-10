#!/usr/bin/env bash
set -euo pipefail

if grep '^Listen 80$' /etc/httpd/conf/httpd.conf > /dev/null 2>&1; then
	sed -i 's/^Listen 80$/Listen 8080/g' /etc/httpd/conf/httpd.conf
fi

systemctl start httpd
