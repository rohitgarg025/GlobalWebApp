# Hosting: Fly.io or AWS

The app runs unchanged on either host. The **deploy target** is chosen by the GitHub repository
variable `DEPLOY_TARGET`:

| `DEPLOY_TARGET` | A push to `main` deploys to |
|---|---|
| *(unset)* | nowhere (the workflow just prints a notice) |
| `fly` | Fly.io (backend + frontend apps) |
| `aws` | AWS (EC2 + S3/CloudFront) |
| `both` | both |

To deploy once to a different target, use **Actions → Deploy → Run workflow → target**.
From your Mac: `scripts/deploy.sh --target fly|aws`.

---

## AWS layout (region ap-south-1, Mumbai)

The stack has two modes, chosen by `USE_CLOUDFRONT` (stack parameter `UseCloudFront`):

**Direct mode** (`USE_CLOUDFRONT=false`, the current default; no CloudFront needed)
```
Browser ─HTTPS─► https://<ip-with-dashes>.sslip.io  → EC2 :443 Caddy (free Let's Encrypt certificate)
                   ├─ /*      → /opt/gbe/www (copy of the S3 site bucket)
                   └─ /api/*  → Docker container "gbe" on 127.0.0.1:8000 (FastAPI)
```

**CloudFront mode** (`USE_CLOUDFRONT=true`, once AWS has verified the account)
```
Browser ─HTTPS─► CloudFront https://<id>.cloudfront.net
                   ├─ /*      → S3 (Flutter web build)
                   └─ /api/*  → EC2 :80 (only CloudFront allowed) → Docker container "gbe" (FastAPI)
```
Both modes: EC2 (t3.small + 2 GB swap), with an EBS volume at `/data` holding uploaded files (`drawings/`, `takeoff/`, `bbs/`) and `caddy/`, snapshotted daily (7 kept).

**Database:** Amazon RDS PostgreSQL `gbe-db` (stack parameter `UseRds=true`, since Nov 2026). It runs PostgreSQL 17 on `db.t4g.micro` with 20 GB that grows automatically, in private subnets, and only the server can reach it on port 5432. The app finds it through `/gbe/DATABASE_URL` (SSM SecureString). Without that parameter the app falls back to SQLite at `/data/app.db`. See "Database (RDS)" below.

- The app and API share one address in both modes, so there's no CORS setup and no domain is needed. `sslip.io` is a free DNS service: `13-201-5-9.sslip.io` resolves to `13.201.5.9`.
- The server reads its mode from SSM (`/gbe-infra/mode`) on every `run.sh`, so switching modes doesn't replace the server or its data.

### Switching to CloudFront after account verification
New AWS accounts must be **verified before they can create CloudFront distributions**. To ask, go to Support Center → **Create case** → Account and billing → Account. Write "Please verify my account so I can create CloudFront distributions", and paste the CloudFormation error, including its request ID.

Once AWS confirms:
1. Run `USE_CLOUDFRONT=true scripts/deploy.sh infra`. This is a stack update; the instance and data are kept.
2. Update `/gbe/ALLOWED_ORIGINS` to the new CloudFront URL:
   ```bash
   aws ssm put-parameter --overwrite --name /gbe/ALLOWED_ORIGINS --value 'https://<id>.cloudfront.net'
   ```
3. Update the GitHub variables `AWS_APP_URL` and `AWS_DISTRIBUTION_ID` (both printed by step 1).
4. Re-run the workflow with target `aws`, or run `/opt/gbe/run.sh` on the server through Session Manager. Caddy stops, and the API moves to port 80 behind CloudFront.

The sslip.io address stops working after the switch; use the CloudFront URL from then on.
- The server has **no SSH**. Get a shell through **SSM Session Manager** (EC2 console → instance → Connect → Session Manager).
- Secrets live in **SSM Parameter Store** under `/gbe/` and are read by `/opt/gbe/run.sh` each time the container starts.

### Cost (approx.)
| Item | Cost |
|---|---|
| t3.small | ~$17/month (Free Tier credits apply) |
| Data disk and snapshots | ~$5 |
| CloudFront, S3, ECR | ~$2, mostly within Free Tier |
| Public IPv4 address | ~$3.6 |
| RDS PostgreSQL db.t4g.micro + 20 GB | ~$15–20 (Free plan credits apply) |

Switch to `t3.medium` (4 GB, ~$33) if large DWG conversions are slow or fail:
`INSTANCE_TYPE=t3.medium scripts/deploy.sh infra` (about 2 minutes; the data is kept).

---

## One-time setup

1. **CLI access to your AWS account.** Create an IAM user with `AdministratorAccess` (IAM → Users → Create user → Access keys → CLI), then:
   ```bash
   brew install awscli
   ```
   ```bash
   aws configure    # paste the key pair, region ap-south-1, output json
   ```
2. **Create the stack.** This takes about 10 minutes, mostly for CloudFront. It prints the app URL and the GitHub variables:
   ```bash
   scripts/deploy.sh infra
   ```
3. **Secrets.** Run these once each; the values are never committed:
   ```bash
   aws ssm put-parameter --region ap-south-1 --type SecureString --name /gbe/AUTH_SECRET_KEY --value "$(openssl rand -hex 32)"
   ```
   ```bash
   aws ssm put-parameter --region ap-south-1 --type SecureString --name /gbe/ANTHROPIC_API_KEY --value 'sk-ant-…'
   ```
   ```bash
   aws ssm put-parameter --region ap-south-1 --type String --name /gbe/ADMIN_EMAILS --value 'you@company.com'
   ```
   ```bash
   aws ssm put-parameter --region ap-south-1 --type String --name /gbe/ALLOWED_ORIGINS --value 'https://<id>.cloudfront.net'
   ```
   Optional, once Google sign-in is configured: `/gbe/GOOGLE_CLIENT_ID`.
   Dev login ("Skip — Enter as Dev / Admin") stays **enabled**. To turn it off later, set `/gbe/DISABLE_DEV_LOGIN` = `1` and redeploy the backend.
4. **GitHub variables.** Add the values printed in step 2 under repo Settings → Secrets and variables → Actions → **Variables**: `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `AWS_ECR_URI`, `AWS_INSTANCE_ID`, `AWS_SITE_BUCKET`, `AWS_DISTRIBUTION_ID`, `AWS_APP_URL`, `DEPLOY_TARGET`.
5. **First deploy.** Push to `main` with `DEPLOY_TARGET=aws`, or run the workflow manually with target `aws`.

## Fly.io setup (for `fly` / `both`)
- **Persistent disk, once:**
  ```bash
  fly volumes create gbe_data --region bom --size 3 -a globalbuildestatewebapp-backend
  ```
  `backend/fly.toml` mounts it at `/data`.
- **Session key:**
  ```bash
  fly secrets set AUTH_SECRET_KEY=$(openssl rand -hex 32) -a globalbuildestatewebapp-backend
  ```
  Also set `ANTHROPIC_API_KEY` there.
- **GitHub secret `FLY_API_TOKEN`:** create it with `fly tokens create deploy`.

---

## Day-to-day

| Task | How |
|---|---|
| Logs | Session Manager → `sudo docker logs --tail 200 -f gbe` |
| Restart | Session Manager → `sudo /opt/gbe/run.sh` |
| Roll back | `sudo /opt/gbe/run.sh <older-git-sha>` (ECR keeps the last 10 images) |
| Change a secret | `aws ssm put-parameter --overwrite …`, then restart |
| Health | `curl https://<id>.cloudfront.net/api/health` |

### Restore data from a snapshot
1. EC2 → Snapshots, filter by tag `Backup = gbe-daily`, choose the date, then **Create volume** in the same AZ as the server.
2. Session Manager: `sudo docker stop gbe && sudo umount /data`.
3. Detach the current data volume, attach the restored one as `/dev/sdf`, then `sudo mount -a && sudo /opt/gbe/run.sh`.

### Database (RDS)
- **Connection:** `/gbe/DATABASE_URL` = `postgresql+psycopg://gbe_app:<password>@<DbEndpoint>:5432/gbe`.
  - The password is stored only in `/gbe-infra/db_password`, an SSM SecureString. The stack reads it when creating the database.
  - The endpoint is the stack output `DbEndpoint`.
- **Schema:** the app creates and updates the schema itself on start-up with Alembic. See `backend/alembic/README.md`.
- **Backups:**
  - Point-in-time restore covers `DbBackupDays`. It is **1 day** because the account is on the AWS Free plan, which refuses 7.
  - After upgrading the account plan, raise it with `aws cloudformation deploy … --parameter-overrides DbBackupDays=7`, or in the RDS console under Modify → Backup retention.
  - Restore: RDS console → `gbe-db` → Actions → **Restore to point in time**. This creates a new instance; point `/gbe/DATABASE_URL` at it and run `sudo /opt/gbe/run.sh`.
- **Deletion protection:** it is on, and deleting the stack leaves a final snapshot.
- **Reporting tools:** they can't reach the database directly because it is private. Use an SSM port-forward through the server:
  ```bash
  aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=<DbEndpoint>,portNumber=5432,localPortNumber=5432
  ```
  Then connect to `localhost:5432`.
- **Server AMI:** stack parameter `ServerAmiId` pins the running server's image. Without it, any stack update would pick up the newest Amazon Linux and replace the server. `scripts/deploy.sh` keeps the pinned value.
- **Pending one-line UserData change:** the template's `run.sh` pull-fallback line was patched by hand on the live server, but the stack hasn't applied it yet. The next `scripts/deploy.sh infra` will apply it, which stops and starts the server for about 2 minutes.

### Deleting everything
Turn off RDS deletion protection first (RDS console → `gbe-db` → Modify). Then run `aws cloudformation delete-stack --stack-name gbe --region ap-south-1`. The data volume and the database are kept as final snapshots (`DeletionPolicy: Snapshot`), and ECR images are removed. Empty the S3 bucket first
(`aws s3 rm s3://<bucket> --recursive`), or the delete stops at the bucket.
