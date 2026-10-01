#!/usr/bin/env bash
set -e

export TF_VAR_subscription_id=$(az account show --query id -o tsv)

terraform -chdir=terraform init
terraform -chdir=terraform apply

RG=$(terraform -chdir=terraform output -raw resource_group)
APP=$(terraform -chdir=terraform output -raw app_name)

rm -f app.zip
zip -r app.zip app requirements.txt
az webapp deploy -g "$RG" -n "$APP" --src-path app.zip --type zip

echo "API: $(terraform -chdir=terraform output -raw api_url)"
