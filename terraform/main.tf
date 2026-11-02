provider "aws" {
  region  = var.region
  profile = "dev"
}

locals {
  # Naming convention
  resource_name = "${var.name_prefix}-${var.environment}"

  s3_origin_id = "distribution-s3-origin"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# CLOUDFRONT S3 ORIGIN BUCKET WITH ACCESS BLOCK AND VERSIONING ENABLED
resource "aws_s3_bucket" "origin_bucket" {
  bucket           = format("${var.name_prefix}-origin-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  bucket_namespace = "account-regional"
  force_destroy    = true

  tags = {
    Name        = local.resource_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "origin_bucket_access_block" {
  bucket = aws_s3_bucket.origin_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "origin_bucket_versioning" {
  bucket = aws_s3_bucket.origin_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


# CLOUDFRONT DISTRIBUTION PERMISSION TO READ OBJECTS IN ORIGIN BUCKET
data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = [
      "${aws_s3_bucket.origin_bucket.arn}/*",
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin_bucket_policy_attachment" {
  bucket = aws_s3_bucket.origin_bucket.id
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
}


# CLOUDFRONT ACCESS CONTROL AND DISTRIBUTION
resource "aws_cloudfront_origin_access_control" "distribution_oac" {
  name                              = "${var.name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name              = aws_s3_bucket.origin_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.distribution_oac.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # AWS Managed Caching Policy (CachingOptimized)
  default_cache_behavior {
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  tags = {
    Name        = local.resource_name
    Environment = var.environment
  }
}


# LOGS DELIVERY DESTINTION S3 BUCKET WITH ACCESS BLOCK
resource "aws_s3_bucket" "logs_bucket" {
  bucket           = format("${var.name_prefix}-cloudfront-logs-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  bucket_namespace = "account-regional"
  force_destroy    = true

  tags = {
    Name        = local.resource_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "logs_bucket_access_block" {
  bucket = aws_s3_bucket.logs_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# DELIVERY PERMISSION TO WRITE OBJECTS TO LOGS BUCKET
data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.logs_bucket.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_log_delivery_source.distribution_logs_source.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "logs_bucket_policy_attachment" {
  bucket = aws_s3_bucket.logs_bucket.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}


# CLOUDFRONT LOGGING DELIVERY SOURCE
resource "aws_cloudwatch_log_delivery_source" "distribution_logs_source" {
  region = "us-east-1"

  name         = "${var.name_prefix}-cloudfront-log-source"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.distribution.arn

  tags = {
    Name        = local.resource_name
    Environment = var.environment
  }
}


# CLOUDFRONT LOGGING DELIVERY DESTINATION
resource "aws_cloudwatch_log_delivery_destination" "distribution_logs_destination" {
  region = "us-east-1"

  name          = "${var.name_prefix}-cloudfront-logs-destination"
  output_format = "parquet"

  delivery_destination_configuration {
    destination_resource_arn = "${aws_s3_bucket.logs_bucket.arn}/logs"
  }

  tags = {
    Name        = local.resource_name
    Environment = var.environment
  }
}


resource "aws_cloudwatch_log_delivery" "distribution_log" {
  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.distribution_logs_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.distribution_logs_destination.arn

  record_fields = [
    "timestamp",
    "date",
    "time",
    "x-edge-location",
    "sc-bytes",
    "c-ip",
    "cs(Host)",
    "cs(Referer)",
    "cs(User-Agent)",
    "sc-status",
    "x-edge-result-type",
    "x-edge-request-id",
    "cs-bytes",
    "time-taken",
    "x-forwarded-for",
    "time-to-first-byte",
    "c-country",
    "distributionid"
  ]

  s3_delivery_configuration {
    enable_hive_compatible_path = true
    suffix_path                 = "/{yyyy}/{MM}/{dd}/"
  }
}