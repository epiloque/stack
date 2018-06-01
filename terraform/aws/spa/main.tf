variable "namespace" {
  description = "Namespace, which could be your organization name"
  type        = "string"
}

variable "stage" {
  description = "Stage, e.g. 'prod', 'staging', 'dev', or 'test'"
  type        = "string"
}

variable "name" {
  description = "Name  (e.g. `bastion` or `db`)"
  type        = "string"
}

variable "delimiter" {
  type        = "string"
  default     = "-"
  description = "Delimiter to be used between `name`, `namespace`, `stage`, etc."
}

variable "attributes" {
  type        = "list"
  default     = []
  description = "Additional attributes (e.g. `policy` or `role`)"
}

variable "tags" {
  type        = "map"
  default     = {}
  description = "Additional tags (e.g. map('BusinessUnit`,`XYZ`)"
}

//

variable "acm_certificate_arn" {
  description = "Existing ACM Certificate ARN"
  default     = ""
}

variable "aliases" {
  type        = "list"
  description = "List of FQDN's - Used to set the Alternate Domain Names (CNAMEs) setting on Cloudfront"
  default     = []
}

variable "origin_bucket" {
  default = ""
}

variable "origin_path" {
  # http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-values-specify.html#DownloadDistValuesOriginPath
  description = "(Optional) - An optional element that causes CloudFront to request your content from a directory in your Amazon S3 bucket or your custom origin. It must begin with a /. Do not add a / at the end of the path."
  default     = ""
}

variable "origin_force_destroy" {
  default = "false"
}

variable "bucket_domain_format" {
  default = "%s.s3.amazonaws.com"
}

variable "compress" {
  default = "true"
}

variable "enabled" {
  default = "true"
}

variable "is_ipv6_enabled" {
  default = "true"
}

variable "default_root_object" {
  default = "index.html"
}

variable "response_page_path" {
  default = "/index.html"
}

variable "comment" {
  default = "Managed by Terraform"
}

variable "log_include_cookies" {
  default = "false"
}

variable "log_prefix" {
  default = ""
}

variable "log_standard_transition_days" {
  description = "Number of days to persist in the standard storage tier before moving to the glacier tier"
  default     = "30"
}

variable "log_glacier_transition_days" {
  description = "Number of days after which to move the data to the glacier storage tier"
  default     = "60"
}

variable "log_expiration_days" {
  description = "Number of days after which to expunge the objects"
  default     = "90"
}

variable "forward_query_string" {
  default = "false"
}

variable "cors_allowed_headers" {
  type    = "list"
  default = ["*"]
}

variable "cors_allowed_methods" {
  type    = "list"
  default = ["GET"]
}

variable "cors_allowed_origins" {
  type    = "list"
  default = []
}

variable "cors_expose_headers" {
  type    = "list"
  default = ["ETag"]
}

variable "cors_max_age_seconds" {
  default = "3600"
}

variable "forward_cookies" {
  default = "none"
}

variable "price_class" {
  default = "PriceClass_100"
}

variable "viewer_protocol_policy" {
  description = "allow-all, redirect-to-https"
  default     = "redirect-to-https"
}

variable "allowed_methods" {
  type    = "list"
  default = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
}

variable "cached_methods" {
  type    = "list"
  default = ["GET", "HEAD"]
}

variable "default_ttl" {
  default = "60"
}

variable "min_ttl" {
  default = "0"
}

variable "max_ttl" {
  default = "31536000"
}

variable "geo_restriction_type" {
  # e.g. "whitelist"
  default = "none"
}

variable "geo_restriction_locations" {
  type = "list"

  # e.g. ["US", "CA", "GB", "DE"]
  default = []
}

/* variable "parent_zone_id" { */
/*   default = "" */
/* } */
/*  */
/* variable "parent_zone_name" { */
/*   default = "" */
/* } */

/* variable "null" { */
/*   description = "an empty string" */
/*   default     = "" */
/* } */

/**
* SPA
*/

module "label" {
  source     = "../../generic/null-label"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

resource "aws_cloudfront_origin_access_identity" "default" {
  comment = "${module.label.id}"
}

data "aws_iam_policy_document" "origin" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::$${bucket_name}$${origin_path}*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.default.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::$${bucket_name}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.default.iam_arn}"]
    }
  }
}

data "template_file" "default" {
  template = "${data.aws_iam_policy_document.origin.json}"

  vars {
    origin_path = "${coalesce(var.origin_path, "/")}"
    bucket_name = "${null_resource.default.triggers.bucket}"
  }
}

resource "aws_s3_bucket_policy" "default" {
  bucket = "${null_resource.default.triggers.bucket}"
  policy = "${data.template_file.default.rendered}"
}

resource "aws_s3_bucket" "origin" {
  count         = "${signum(length(var.origin_bucket)) == 1 ? 0 : 1}"
  bucket        = "${module.label.id}"
  acl           = "private"
  tags          = "${module.label.tags}"
  force_destroy = "${var.origin_force_destroy}"

  cors_rule {
    allowed_headers = "${var.cors_allowed_headers}"
    allowed_methods = "${var.cors_allowed_methods}"
    allowed_origins = "${sort(distinct(compact(concat(var.cors_allowed_origins, var.aliases))))}"
    expose_headers  = "${var.cors_expose_headers}"
    max_age_seconds = "${var.cors_max_age_seconds}"
  }
}

module "logs" {
  source                   = "../log-storage"
  namespace                = "${var.namespace}"
  stage                    = "${var.stage}"
  name                     = "${var.name}"
  delimiter                = "${var.delimiter}"
  attributes               = ["${compact(concat(var.attributes, list("logs")))}"]
  tags                     = "${var.tags}"
  prefix                   = "${var.log_prefix}"
  standard_transition_days = "${var.log_standard_transition_days}"
  glacier_transition_days  = "${var.log_glacier_transition_days}"
  expiration_days          = "${var.log_expiration_days}"
}

resource "null_resource" "default" {
  triggers {
    bucket             = "${element(compact(concat(list(var.origin_bucket), aws_s3_bucket.origin.*.bucket)), 0)}"
    bucket_domain_name = "${format(var.bucket_domain_format, element(compact(concat(list(var.origin_bucket), aws_s3_bucket.origin.*.bucket)), 0))}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "default" {
  enabled             = "${var.enabled}"
  is_ipv6_enabled     = "${var.is_ipv6_enabled}"
  comment             = "${var.comment}"
  default_root_object = "${var.default_root_object}"
  price_class         = "${var.price_class}"
  depends_on          = ["aws_s3_bucket.origin"]

  logging_config = {
    include_cookies = "${var.log_include_cookies}"
    bucket          = "${module.logs.bucket_domain_name}"
    prefix          = "${var.log_prefix}"
  }

  aliases = ["${var.aliases}"]

  origin {
    domain_name = "${null_resource.default.triggers.bucket_domain_name}"
    origin_id   = "${module.label.id}"
    origin_path = "${var.origin_path}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path}"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = "${var.acm_certificate_arn}"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1"
    cloudfront_default_certificate = "${var.acm_certificate_arn == "" ? true : false}"
  }

  default_cache_behavior {
    allowed_methods  = "${var.allowed_methods}"
    cached_methods   = "${var.cached_methods}"
    target_origin_id = "${module.label.id}"
    compress         = "${var.compress}"

    forwarded_values {
      query_string = "${var.forward_query_string}"

      cookies {
        forward = "${var.forward_cookies}"
      }
    }

    viewer_protocol_policy = "${var.viewer_protocol_policy}"
    default_ttl            = "${var.default_ttl}"
    min_ttl                = "${var.min_ttl}"
    max_ttl                = "${var.max_ttl}"
  }

  restrictions {
    geo_restriction {
      restriction_type = "${var.geo_restriction_type}"
      locations        = "${var.geo_restriction_locations}"
    }
  }

  custom_error_response {
    error_caching_min_ttl = "${var.default_ttl}"
    error_code            = 404
    response_code         = 200
    response_page_path    = "${var.response_page_path}"
  }

  tags = "${module.label.tags}"
}

output "cf_id" {
  value = "${aws_cloudfront_distribution.default.id}"
}

output "cf_arn" {
  value = "${aws_cloudfront_distribution.default.arn}"
}

output "cf_status" {
  value = "${aws_cloudfront_distribution.default.status}"
}

output "cf_domain_name" {
  value = "${aws_cloudfront_distribution.default.domain_name}"
}

output "cf_etag" {
  value = "${aws_cloudfront_distribution.default.etag}"
}

output "cf_hosted_zone_id" {
  value = "${aws_cloudfront_distribution.default.hosted_zone_id}"
}

output "s3_bucket" {
  value = "${null_resource.default.triggers.bucket}"
}

output "s3_bucket_domain_name" {
  value = "${null_resource.default.triggers.bucket_domain_name}"
}
