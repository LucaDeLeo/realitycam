#!/bin/bash
set -e

echo "Creating S3 bucket for RealityCam..."
awslocal s3 mb s3://realitycam-media-dev
echo "S3 bucket realitycam-media-dev created successfully"
