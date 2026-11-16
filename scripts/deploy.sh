#!/usr/bin/env bash
# Manual deploys from your Mac (the GitHub "Deploy" workflow does the same on push).
#
#   scripts/deploy.sh infra                    create/update the AWS stack, print GitHub variables
#   scripts/deploy.sh --target fly             deploy backend + frontend to Fly.io
#   scripts/deploy.sh --target aws             deploy backend (needs Docker) + frontend to AWS
#   scripts/deploy.sh --target aws --frontend  AWS frontend only
#
# Env: AWS_REGION (default ap-south-1), STACK (default gbe), INSTANCE_TYPE (default t3.small),
#      USE_CLOUDFRONT (default false; set true once AWS has verified the account for CloudFront)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-ap-south-1}"
STACK="${STACK:-gbe}"
FLY_BACKEND_URL="https://globalbuildestatewebapp-backend.fly.dev"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 is not installed ($2)"; }
out() {  # stack output by key
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

infra() {
  need aws "brew install awscli; then aws configure"
  local pl oidc
  pl=$(aws ec2 describe-managed-prefix-lists --region "$REGION" \
        --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
        --query 'PrefixLists[0].PrefixListId' --output text)
  [ -n "$pl" ] && [ "$pl" != None ] || die "CloudFront prefix list not found in $REGION"
  oidc=true
  if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text \
       | grep -q token.actions.githubusercontent.com; then
    # reuse an existing provider unless this stack created it
    aws cloudformation describe-stack-resource --region "$REGION" --stack-name "$STACK" \
      --logical-resource-id GitHubOidc >/dev/null 2>&1 || oidc=false
  fi
  echo "Deploying stack $STACK in $REGION (instance ${INSTANCE_TYPE:-t3.small}, CloudFront ${USE_CLOUDFRONT:-false})…"
  aws cloudformation deploy --region "$REGION" --stack-name "$STACK" \
    --template-file "$ROOT/infra/aws/stack.yaml" --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides CloudFrontPrefixListId="$pl" CreateGitHubOidcProvider="$oidc" \
      InstanceType="${INSTANCE_TYPE:-t3.small}" UseCloudFront="${USE_CLOUDFRONT:-false}" \
    --no-fail-on-empty-changeset
  cat <<EOF

Stack ready. App URL: $(out AppUrl)

Add these as GitHub repository variables (Settings → Secrets and variables → Actions → Variables):
  AWS_REGION           = $REGION
  AWS_DEPLOY_ROLE_ARN  = $(out DeployRoleArn)
  AWS_ECR_URI          = $(out EcrRepositoryUri)
  AWS_INSTANCE_ID      = $(out InstanceId)
  AWS_SITE_BUCKET      = $(out SiteBucketName)
  AWS_DISTRIBUTION_ID  = $(out DistributionId)   (leave empty in direct mode)
  AWS_APP_URL          = $(out AppUrl)
  DEPLOY_TARGET        = aws   (or fly / both)
EOF
}

deploy_fly() {
  need flyctl "brew install flyctl; then fly auth login"
  (cd "$ROOT/backend" && flyctl deploy --remote-only)
  (cd "$ROOT/flutter_app" && flyctl deploy --remote-only --build-arg API_URL="$FLY_BACKEND_URL")
}

deploy_aws_backend() {
  need aws "brew install awscli"
  command -v docker >/dev/null || die "Docker isn't installed here - push to main (or run the GitHub Deploy workflow with target=aws) to deploy the backend."
  local image tag cmd
  image=$(out EcrRepositoryUri); tag=$(git -C "$ROOT" rev-parse --short HEAD)
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${image%%/*}"
  docker build --platform linux/amd64 -t "$image:$tag" -t "$image:latest" "$ROOT/backend"
  docker push "$image:$tag"; docker push "$image:latest"
  cmd=$(aws ssm send-command --region "$REGION" --instance-ids "$(out InstanceId)" \
        --document-name AWS-RunShellScript --parameters "commands=[\"/opt/gbe/run.sh $tag\"]" \
        --query Command.CommandId --output text)
  echo "Restarting container (SSM command $cmd)…"
  aws ssm wait command-executed --region "$REGION" --command-id "$cmd" --instance-id "$(out InstanceId)"
}

deploy_aws_frontend() {
  need aws "brew install awscli"
  need flutter "Flutter SDK"
  local bucket
  bucket=$(out SiteBucketName)
  (cd "$ROOT/flutter_app" && flutter build web --release --dart-define=API_URL=)
  cd "$ROOT/flutter_app/build/web"
  aws s3 sync . "s3://$bucket" --delete --cache-control "public,max-age=31536000,immutable" \
    --exclude index.html --exclude flutter_service_worker.js --exclude main.dart.js \
    --exclude flutter_bootstrap.js --exclude version.json --exclude manifest.json
  for f in index.html flutter_service_worker.js main.dart.js flutter_bootstrap.js version.json manifest.json; do
    [ -f "$f" ] && aws s3 cp "$f" "s3://$bucket/$f" --cache-control no-cache
  done
  local dist
  dist=$(out DistributionId)
  if [ -n "$dist" ] && [ "$dist" != None ]; then
    aws cloudfront create-invalidation --distribution-id "$dist" \
      --paths "/index.html" "/" "/main.dart.js" "/flutter_bootstrap.js" "/flutter_service_worker.js" >/dev/null
  else
    local cmd
    cmd=$(aws ssm send-command --region "$REGION" --instance-ids "$(out InstanceId)" \
          --document-name AWS-RunShellScript --parameters 'commands=["/opt/gbe/run.sh site"]' \
          --query Command.CommandId --output text)
    aws ssm wait command-executed --region "$REGION" --command-id "$cmd" --instance-id "$(out InstanceId)"
  fi
  echo "Frontend deployed: $(out AppUrl)"
}

case "${1:-}" in
  infra) infra ;;
  --target)
    case "${2:-}" in
      fly) deploy_fly ;;
      aws) if [ "${3:-}" = --frontend ]; then deploy_aws_frontend; else deploy_aws_backend; deploy_aws_frontend; fi ;;
      *) die "--target must be fly or aws" ;;
    esac ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
