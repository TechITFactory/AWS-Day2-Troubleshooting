#!/bin/bash
# modules/web-app/user-data.sh
# Bootstraps a NorthBank "web server": installs nginx, serves a tiny banking
# landing page and a /health endpoint the ALB target group checks.
#
# Rendered by Terraform via templatefile(); ${app_name} is injected.
set -euxo pipefail

dnf install -y nginx

# Health endpoint the ALB target group hits (must return HTTP 200). This MUST
# be a plain file, not a directory -- nginx 301-redirects a bare "/health"
# request to "/health/" when it matches a directory, and the ALB health check
# does not follow redirects, so a directory here permanently fails health
# checks (confirmed by hand: every instance was stuck "unhealthy" with
# Target.ResponseCodeMismatch on code 301 until this was a file).
echo "OK" > /usr/share/nginx/html/health

# The "app" — a placeholder NorthBank banking page that reports its instance id
# so students can see load balancing across the ASG.
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")

cat > /usr/share/nginx/html/index.html <<PAGE
<!doctype html>
<title>NorthBank — Digital Banking (${app_name})</title>
<h1>NorthBank retail banking</h1>
<p>Served by instance: <code>$INSTANCE_ID</code></p>
<p>Status: <strong>healthy</strong></p>
PAGE

systemctl enable --now nginx
