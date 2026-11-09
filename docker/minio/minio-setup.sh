#!/bin/sh
# Idempotente: roda a cada `make up`. Cria o bucket privado e o usuário da API
# com acesso restrito a ele.
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null

mc mb --ignore-existing "local/$S3_BUCKET"
mc anonymous set none "local/$S3_BUCKET" >/dev/null

policy=/tmp/condoguard-api-policy.json
cat >"$policy" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::$S3_BUCKET"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::$S3_BUCKET/*"]
    }
  ]
}
EOF

mc admin policy create local condoguard-api "$policy" >/dev/null
mc admin user add local "$S3_ACCESS_KEY" "$S3_SECRET_KEY" >/dev/null
mc admin policy attach local condoguard-api --user "$S3_ACCESS_KEY" >/dev/null 2>&1 || true

echo "minio-setup: bucket '$S3_BUCKET' e usuário da API prontos"
