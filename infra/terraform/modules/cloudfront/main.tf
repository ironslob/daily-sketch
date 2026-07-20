locals {
  common_tags = merge(var.tags, {
    Module = "cloudfront"
  })

  use_custom_domain = length(var.aliases) > 0 && var.acm_certificate_arn != null
}

resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.name_prefix}-media-oac"
  description                       = "OAC for Daily Sketch derivative media"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "cdn_path_guard" {
  name    = replace("${var.name_prefix}-cdn-path-guard", "-", "_")
  runtime = "cloudfront-js-2.0"
  comment = "Allow only /display and /thumbnail derivative keys; block /original"
  publish = true

  code = <<-EOF
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri.indexOf("/original") !== -1) {
        return {
            statusCode: 403,
            statusDescription: "Forbidden",
            headers: { "content-type": { value: "text/plain" } },
            body: "Original media is never served via CDN."
        };
    }

    if (!(uri.endsWith("/display") || uri.endsWith("/thumbnail"))) {
        return {
            statusCode: 403,
            statusDescription: "Forbidden",
            headers: { "content-type": { value: "text/plain" } },
            body: "Only display and thumbnail derivatives are CDN-cacheable."
        };
    }

    return request;
}
EOF
}

resource "aws_cloudfront_distribution" "media" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} derivative media CDN"
  default_root_object = ""
  price_class         = var.price_class
  aliases             = local.use_custom_domain ? var.aliases : []

  origin {
    domain_name              = var.media_bucket_regional_domain_name
    origin_id                = "media-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "media-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.cdn_path_guard.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "users/*/uploads/*/display"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "media-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.cdn_path_guard.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "users/*/uploads/*/thumbnail"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "media-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.cdn_path_guard.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.use_custom_domain ? [1] : []
    content {
      acm_certificate_arn      = var.acm_certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.use_custom_domain ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-media-cdn"
  })
}
