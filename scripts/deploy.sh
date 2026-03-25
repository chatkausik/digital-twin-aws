#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."        # project root
echo "Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Terraform workspace & apply
cd terraform
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Build common var args
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
if [ "$ENVIRONMENT" = "prod" ]; then
  TF_VAR_ARGS=(-var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT")
else
  TF_VAR_ARGS=(-var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT")
fi

# Import a resource into state if it exists in AWS but not in state
import_if_missing() {
  local resource="$1"
  local id="$2"
  if ! terraform state show "$resource" > /dev/null 2>&1; then
    echo "Importing $resource..."
    terraform import "${TF_VAR_ARGS[@]}" "$resource" "$id" || true
  fi
}

# Reconcile resources that may exist in AWS but be missing from state
echo "Checking for existing resources to import..."

# IAM role
import_if_missing "aws_iam_role.lambda_role" "${NAME_PREFIX}-lambda-role"

# CloudFront distribution (only if custom domain is configured)
ROOT_DOMAIN=$(terraform output -raw root_domain 2>/dev/null || true)
if [ -z "$ROOT_DOMAIN" ] && [ "$ENVIRONMENT" = "prod" ]; then
  ROOT_DOMAIN="kausik-digital-twin.com"
fi

if [ -n "$ROOT_DOMAIN" ]; then
  CF_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Aliases.Items, '${ROOT_DOMAIN}')].Id | [0]" \
    --output text 2>/dev/null || true)

  if [ -n "$CF_ID" ] && [ "$CF_ID" != "None" ]; then
    import_if_missing "aws_cloudfront_distribution.main" "$CF_ID"
  fi

  # ACM certificate (must be in us-east-1 for CloudFront)
  CERT_ARN=$(aws acm list-certificates --region us-east-1 \
    --query "CertificateSummaryList[?DomainName=='${ROOT_DOMAIN}'].CertificateArn | [0]" \
    --output text 2>/dev/null || true)

  if [ -n "$CERT_ARN" ] && [ "$CERT_ARN" != "None" ]; then
    import_if_missing "aws_acm_certificate.site[0]" "$CERT_ARN"
  fi

  # Route53 validation CNAME records
  ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "${ROOT_DOMAIN}" \
    --query "HostedZones[0].Id" --output text 2>/dev/null | cut -d'/' -f3 || true)

  if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "None" ]; then
    # List existing validation CNAMEs and import each one
    while IFS= read -r record_name; do
      [ -z "$record_name" ] && continue
      # Derive the for_each key (domain the cert covers) from the record name
      if [[ "$record_name" == *".www."* ]]; then
        key="www.${ROOT_DOMAIN}"
      else
        key="${ROOT_DOMAIN}"
      fi
      import_if_missing \
        "aws_route53_record.site_validation[\"${key}\"]" \
        "${ZONE_ID}_${record_name}_CNAME"
    done < <(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
      --query "ResourceRecordSets[?Type=='CNAME' && starts_with(Name, '_')].Name" \
      --output text 2>/dev/null | tr '\t' '\n' | sed 's/\.$//' || true)
  fi
fi

echo "Applying Terraform..."
terraform apply "${TF_VAR_ARGS[@]}" -auto-approve

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Build + deploy frontend
cd ../frontend

# Create production environment file with API URL
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd ..

# 4. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"