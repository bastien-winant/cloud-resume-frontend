output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value = aws_cloudfront_distribution.distribution.arn
}

output "origin_bucket_arn" {
  description = "ARN of the CloudFront origin S3 bucket"
  value = aws_s3_bucket.origin_bucket.arn
}

output "logs_bucket_arn" {
  description = "ARN of the Cloudfront logs destination S3 bucket"
  value = aws_s3_bucket.logs_bucket.arn
}