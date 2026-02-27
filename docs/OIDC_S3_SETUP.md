# OIDC + S3 Setup For Solana Binary Workflows

This runbook configures AWS so GitHub Actions can publish Solana binaries to S3 using OIDC role assumption (no long-lived AWS keys).

Related files in this repo:
- `solana-localnet/build-solana-cli/solv-s3-oidc-trust-policy.json`
- `solana-localnet/build-solana-cli/solv-s3-ci-role-policy.json`
- `solana-localnet/build-solana-cli/solv-store-bucket-policy-ci-only.json`
- `.github/workflows/solana-binary-pipeline.yml`
- `.github/workflows/solana-binary-promote.yml`

## Prerequisites

- AWS CLI is installed and authenticated.
- Your AWS identity can manage IAM roles/policies and S3 bucket policies.
- You know:
  - AWS account ID
  - target role name
  - target S3 bucket (default in workflows is `solv-store`)

## 1) Set environment variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ROLE_NAME="hvk-github-actions-s3-publisher"
export REPO_SLUG="team-supersafe/hayek-validator-kit"
export BUCKET_NAME="solv-store"
```

## 2) Ensure GitHub OIDC provider exists in IAM (CLI-only)

Create-or-verify with AWS CLI:

```bash
PROVIDER_URL="https://token.actions.githubusercontent.com"
PROVIDER_HOST="token.actions.githubusercontent.com"
PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${PROVIDER_HOST}"

if aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "${PROVIDER_ARN}" >/dev/null 2>&1; then
  echo "OIDC provider already exists: ${PROVIDER_ARN}"
else
  aws iam create-open-id-connect-provider \
    --url "${PROVIDER_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
fi

aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "${PROVIDER_ARN}" \
  --query "{Url:Url,ClientIDList:ClientIDList,ThumbprintList:ThumbprintList}" \
  --output yaml
```

Expected:
- URL: `token.actions.githubusercontent.com`
- Client ID list includes: `sts.amazonaws.com`

Note:
- AWS currently validates GitHub via trusted CAs, but `create-open-id-connect-provider` may still require a thumbprint argument depending on CLI/API behavior.

## 3) Render trust policy for your account/repo

The template includes placeholders and a repo scope.

```bash
sed \
  -e "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" \
  -e "s|repo:team-supersafe/hayek-validator-kit:\\*|repo:${REPO_SLUG}:*|g" \
  solana-localnet/build-solana-cli/solv-s3-oidc-trust-policy.json \
  > /tmp/hvk-oidc-trust-policy.json

cat /tmp/hvk-oidc-trust-policy.json
```

## 4) Create or update IAM role used by GitHub Actions

```bash
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document file:///tmp/hvk-oidc-trust-policy.json
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/hvk-oidc-trust-policy.json
fi
```

## 5) Attach the CI S3 access policy to that role

```bash
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "hvk-solana-binary-ci-s3" \
  --policy-document file://solana-localnet/build-solana-cli/solv-s3-ci-role-policy.json
```

## 6) (Recommended) Enforce CI-only writes at bucket level

This denies writes/deletes to managed prefixes unless caller is the CI role.

```bash
sed \
  -e "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" \
  -e "s|<CI_OIDC_ROLE_NAME>|${ROLE_NAME}|g" \
  solana-localnet/build-solana-cli/solv-store-bucket-policy-ci-only.json \
  > /tmp/hvk-bucket-policy-ci-only.json

aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy file:///tmp/hvk-bucket-policy-ci-only.json
```

## 7) Get the role ARN (this is the workflow input value)

```bash
aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text
```

Use that value in GitHub workflow dispatch field:
- `IAM role ARN for GitHub OIDC ...` in `solana-binary-pipeline`
- `IAM role ARN for GitHub OIDC` in `solana-binary-promote`

Example:

`arn:aws:iam::123456789012:role/hvk-github-actions-s3-publisher`

## 8) Suggested first runs

1. Pipeline dry-run first:
   - `dry_run=true`
   - `publish_staging=false`
2. Real staging publish:
   - `dry_run=false`
   - `publish_staging=true`
   - `aws_role_to_assume=<role ARN from step 7>`

## Troubleshooting

- `publish_staging=true requires aws_role_to_assume to be set`:
  - You left role ARN empty in workflow dispatch.
- `Not authorized to perform sts:AssumeRoleWithWebIdentity`:
  - Trust policy mismatch (account ID or repo slug).
- S3 AccessDenied on put/copy:
  - CI role policy missing actions/resources, or bucket policy denies caller ARN.
