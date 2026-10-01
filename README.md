# VNet API

Author: Mayur

A small REST API (Python, FastAPI) that creates an Azure Virtual Network with several subnets,
stores what it created, and lets you read it back.

- Runs on Azure App Service
- Callers authenticate with a Microsoft Entra ID token. Any authenticated user is allowed.
- The app talks to Azure with its managed identity, so there are no secrets
- Created vnets are saved in Azure Table Storage
- Infrastructure is Terraform (it also creates the Entra app registration)

## Endpoints

| Method | Path | |
|---|---|---|
| GET | /health | no auth |
| POST | /vnets | create a vnet with subnets |
| GET | /vnets | list stored vnets |
| GET | /vnets/{id} | get one |

Example body for `POST /vnets`:

```json
{
  "name": "vnet-demo",
  "address_space": ["10.10.0.0/16"],
  "subnets": [
    {"name": "frontend", "address_prefix": "10.10.1.0/24"},
    {"name": "backend", "address_prefix": "10.10.2.0/24"}
  ]
}
```

Subnets must be inside the address space and must not overlap, otherwise you get a 422.
A vnet name that already exists returns 409. No token or a bad token returns 401.

## Layout

```
app/main.py     the API
app/auth.py     token validation
tests/          unit tests (Azure is faked)
terraform/      infrastructure
deploy.sh       terraform apply + code deploy
```

## Tests

```
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

## Deploy

You need Terraform, the Azure CLI (`az login`) and `zip`. Your account needs to be able to create
role assignments and register apps in Entra ID.

```
./deploy.sh
```

This creates the resource group, storage account and table, App Service, the Entra app and the
role assignments (Network Contributor on the resource group, Table Data Contributor on the storage
account), then uploads the code. The first start takes a few minutes while dependencies install.

## Try it

```
API=$(terraform -chdir=terraform output -raw api_url)
CID=$(terraform -chdir=terraform output -raw api_client_id)
TOKEN=$(az account get-access-token --scope api://$CID/access_as_user --query accessToken -o tsv)

curl $API/health
curl $API/vnets                                   # 401, no token

curl -X POST $API/vnets \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"vnet-demo","address_space":["10.10.0.0/16"],"subnets":[{"name":"web","address_prefix":"10.10.1.0/24"},{"name":"db","address_prefix":"10.10.2.0/24"}]}'

curl -H "Authorization: Bearer $TOKEN" $API/vnets
```

Swagger UI is at `$API/docs`.

## Run locally

Copy `.env.example` to `.env` and fill it from `terraform output`, then export the variables and run:

```
az login
set -a; source .env; set +a
uvicorn app.main:app --reload
```

Your user needs Network Contributor on the resource group and Table Data Contributor on the
storage account.

## Notes

- Authorization is open on purpose. A valid token is enough, roles and scopes are not checked.
  To restrict it, check the `scp` or `roles` claim in `auth.py`.
- Creating a vnet waits for Azure to finish, which normally takes a few seconds.
- If Azure creates the vnet but saving to the table fails, the vnet exists but is not in the table.
- Role assignments can take a few minutes to apply after the first deploy.
- Clean up with `terraform -chdir=terraform destroy`.
