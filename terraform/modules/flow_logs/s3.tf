resource "aws_s3_bucket" "archive" {
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles storage cost and is out of scope for a single-region lab.
  #checkov:skip=CKV_AWS_18:Server access logging would need a second bucket; flow log delivery is already authenticated AWS service traffic.
  #checkov:skip=CKV2_AWS_62:No downstream consumer for S3 event notifications in this project.
  #checkov:skip=CKV2_AWS_6:False positive when count = 1: the public access block, versioning, lifecycle and SSE-KMS resources below all target this bucket (asserted in tests).
  #checkov:skip=CKV_AWS_21:See CKV2_AWS_6 (aws_s3_bucket_versioning.archive).
  #checkov:skip=CKV2_AWS_61:See CKV2_AWS_6 (aws_s3_bucket_lifecycle_configuration.archive).
  #checkov:skip=CKV_AWS_145:See CKV2_AWS_6 (aws_s3_bucket_server_side_encryption_configuration.archive).
  count = var.enable_s3_archive ? 1 : 0

  bucket_prefix = "${var.name}-flow-logs-"
  force_destroy = var.s3_force_destroy

  tags = { Name = "${var.name}-flow-logs-archive" }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket                  = aws_s3_bucket.archive[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms ? aws_kms_key.logs[0].arn : null
    }
    bucket_key_enabled = var.enable_kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.s3_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  count = var.enable_s3_archive ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.archive[0].arn, "${aws_s3_bucket.archive[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.archive[0].arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${var.partition}:logs:${var.region}:${var.account_id}:*" }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.archive[0].arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${var.partition}:logs:${var.region}:${var.account_id}:*" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.archive]
}

resource "aws_flow_log" "s3" {
  count = var.enable_s3_archive ? 1 : 0

  vpc_id                   = var.vpc_id
  traffic_type             = var.traffic_type
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.archive[0].arn
  max_aggregation_interval = var.max_aggregation_interval
  log_format               = var.s3_log_format

  destination_options {
    file_format                = "parquet"
    per_hour_partition         = true
    hive_compatible_partitions = var.s3_hive_compatible_partitions
  }

  tags = { Name = "${var.name}-flow-log-s3" }

  depends_on = [aws_s3_bucket_policy.archive]
}
