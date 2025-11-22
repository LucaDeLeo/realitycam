#!/bin/bash
# LocalStack S3 initialization script
# Creates buckets for RealityCam media storage

set -e

echo "Initializing LocalStack S3 buckets..."

# Create media bucket (for photos and depth maps)
awslocal s3 mb s3://realitycam-media-dev

# Create C2PA manifests bucket
awslocal s3 mb s3://realitycam-manifests-dev

# Configure CORS for media bucket (needed for web verification page)
awslocal s3api put-bucket-cors --bucket realitycam-media-dev --cors-configuration '{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedOrigins": ["http://localhost:3000", "http://localhost:3001"],
      "ExposeHeaders": ["ETag", "Content-Length"],
      "MaxAgeSeconds": 3600
    }
  ]
}'

# Set public read policy for verification access
awslocal s3api put-bucket-policy --bucket realitycam-media-dev --policy '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadForVerification",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::realitycam-media-dev/public/*"
    }
  ]
}'

echo "LocalStack S3 initialization complete!"
echo "Buckets created:"
awslocal s3 ls
