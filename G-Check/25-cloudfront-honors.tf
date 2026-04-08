############################################
# Lab 2B-Honors: Origin-Driven Caching
# Uses AWS Managed Policies for production
############################################

# Instead of creating custom policies, use AWS's battle-tested managed policies
# This teaches you the "real" policy names used in production environments

############################################
# AWS Managed Cache Policies
############################################

# "UseOriginCacheControlHeaders" - Trust what the origin says about caching
# If your app sends "Cache-Control: max-age=3600", CloudFront respects it
data "aws_cloudfront_cache_policy" "vandelay_use_origin_headers01" {
  name = "Managed-CachingOptimized"
}

# Same but includes query strings in cache key
# Use when your API truly varies by query string (e.g., /search?q=shoes)
data "aws_cloudfront_cache_policy" "vandelay_use_origin_headers_qs01" {
  name = "Managed-CachingOptimizedForUncompressedObjects"
}

############################################
# AWS Managed Origin Request Policies
############################################

# "AllViewer" - Forward everything the viewer sent to origin
data "aws_cloudfront_origin_request_policy" "vandelay_orp_all_viewer01" {
  name = "Managed-AllViewer"
}

# "AllViewerExceptHostHeader" - Forward everything except Host
# Use when origin needs to see the original request but not the Host header
data "aws_cloudfront_origin_request_policy" "vandelay_orp_all_viewer_except_host01" {
  name = "Managed-AllViewerExceptHostHeader"
}

############################################
# Lab 2B-Honors+: Cache Invalidation
############################################

# This is a "null_resource" that can be triggered to invalidate cache
# Use sparingly - each invalidation costs money and defeats the purpose of caching
resource "null_resource" "vandelay_cache_invalidation01" {
  # Only runs when triggered manually or when specific files change
  triggers = {
    # Change this value to trigger an invalidation
    invalidation_trigger = "initial"
  }

  provisioner "local-exec" {
    command = <<-EOF
      aws cloudfront create-invalidation \
        --distribution-id ${aws_cloudfront_distribution.vandelay_cf01.id} \
        --paths "/static/index.html" "/static/css/*" "/static/js/*"
    EOF
  }

  depends_on = [aws_cloudfront_distribution.vandelay_cf01]
}

############################################
# Outputs
############################################

output "vandelay_managed_cache_policy_optimized" {
  description = "AWS Managed CachingOptimized policy ID"
  value       = data.aws_cloudfront_cache_policy.vandelay_use_origin_headers01.id
}

output "vandelay_invalidation_command" {
  description = "Command to manually invalidate CloudFront cache"
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.vandelay_cf01.id} --paths '/*'"
}
