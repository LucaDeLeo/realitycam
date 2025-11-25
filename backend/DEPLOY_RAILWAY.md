# Deploy to Railway

## Prerequisites

1. [Railway account](https://railway.app)
2. Railway CLI: `npm install -g @railway/cli`

## Quick Deploy

### 1. Login to Railway

```bash
railway login
```

### 2. Create Project

```bash
cd backend
railway init
```

Select "Empty Project" when prompted.

### 3. Add PostgreSQL

```bash
railway add
```

Select "PostgreSQL" from the list.

### 4. Add S3 Storage (via AWS)

You need an AWS S3 bucket. Create one in AWS Console, then set these env vars in Railway:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (e.g., `us-east-1`)
- `S3_BUCKET` (your bucket name)

Or use **Cloudflare R2** (S3-compatible, cheaper):
- `S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com`
- `AWS_ACCESS_KEY_ID` (R2 access key)
- `AWS_SECRET_ACCESS_KEY` (R2 secret key)
- `S3_BUCKET` (R2 bucket name)

### 5. Set Environment Variables

In Railway dashboard or CLI:

```bash
# Required
railway variables set DATABASE_URL='${{Postgres.DATABASE_URL}}'
railway variables set S3_BUCKET='realitycam-media'
railway variables set AWS_ACCESS_KEY_ID='your-key'
railway variables set AWS_SECRET_ACCESS_KEY='your-secret'
railway variables set AWS_REGION='us-east-1'

# Optional
railway variables set RUST_LOG='info'
railway variables set LOG_FORMAT='json'
railway variables set CORS_ORIGINS='https://yourdomain.com'
railway variables set VERIFICATION_BASE_URL='https://yourdomain.com/verify'
```

### 6. Deploy

```bash
railway up
```

First deploy takes ~5-10 minutes (Rust compilation).

### 7. Get Your URL

```bash
railway domain
```

This gives you a public URL like `realitycam-api-production.up.railway.app`.

## Configure iOS App

Update your iOS app's API URL to point to Railway:

```swift
// In APIClient.swift or configuration
let apiBaseURL = "https://your-app.up.railway.app"
```

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string (auto from Railway) |
| `S3_BUCKET` | Yes | S3 bucket name |
| `AWS_ACCESS_KEY_ID` | Yes | AWS/R2 access key |
| `AWS_SECRET_ACCESS_KEY` | Yes | AWS/R2 secret key |
| `AWS_REGION` | Yes | AWS region (e.g., us-east-1) |
| `S3_ENDPOINT` | No | Custom S3 endpoint (for R2/MinIO) |
| `S3_PUBLIC_ENDPOINT` | No | Public URL for photo access |
| `RUST_LOG` | No | Log level (default: info) |
| `LOG_FORMAT` | No | Log format: pretty or json |
| `CORS_ORIGINS` | No | Allowed CORS origins |
| `VERIFICATION_BASE_URL` | No | Base URL for verification links |
| `HOST` | No | Bind host (default: 0.0.0.0) |
| `PORT` | No | Port (Railway sets this automatically) |

## Monitoring

View logs:
```bash
railway logs
```

Open dashboard:
```bash
railway open
```

## Costs

Railway pricing (as of 2024):
- **Hobby**: $5/month, includes $5 credit
- **Pro**: $20/month, usage-based

Typical RealityCam costs:
- Backend: ~$5-10/month
- PostgreSQL: ~$5/month
- Total: ~$10-15/month

## Troubleshooting

### Build fails
- Check Dockerfile has all dependencies
- Ensure `.sqlx/` directory is committed

### Database connection fails
- Verify `DATABASE_URL` is set correctly
- Check PostgreSQL service is running

### S3 upload fails
- Verify AWS credentials are correct
- Check bucket exists and has proper permissions
