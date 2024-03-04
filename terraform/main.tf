provider "aws" {
    region = "us-east-2"
    shared_credentials_files = ["aws-creds"]
    profile                  = "default"
}

resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
}

resource "aws_subnet" "main" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-2a"
}

resource "aws_subnet" "main2" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-2b"
}

resource aws_internet_gateway "main" {
    vpc_id = aws_vpc.main.id
}

resource aws_route_table "main" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }
}

resource "aws_route_table_association" "main" {
    subnet_id = aws_subnet.main.id
    route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "main" {
    vpc_id = aws_vpc.main.id
    name = "pez-sg"

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_s3_bucket" "main" {
    bucket = "pez-bucket"
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "main" {
  depends_on = [
    aws_s3_bucket_ownership_controls.main,
    aws_s3_bucket_public_access_block.main,
  ]

  bucket = aws_s3_bucket.main.id
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "main" {
    bucket = aws_s3_bucket.main.id
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Principal = "*",
                Action = "s3:GetObject",
                Resource = "arn:aws:s3:::pez-bucket/*"
            }
        ]
    })
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.main.id
  key    = "index.html"
  acl    = "public-read"
  content_type = "text/html"
  source = "${path.module}/../website/index.html"
  source_hash = md5(file("${path.module}/../website/index.html"))
}

resource "aws_cloudfront_distribution" "main" {
    origin {
        domain_name = aws_s3_bucket.main.bucket_regional_domain_name
        origin_id = "S3-${aws_s3_bucket.main.id}"
    }

    enabled = true
    is_ipv6_enabled = true
    default_root_object = "index.html"

    default_cache_behavior {
        allowed_methods = ["GET", "HEAD", "OPTIONS"]
        cached_methods = ["GET", "HEAD", "OPTIONS"]
        target_origin_id = "S3-${aws_s3_bucket.main.id}"
        viewer_protocol_policy = "allow-all"

        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }

        min_ttl     = 0
        default_ttl = 3600
        max_ttl     = 86400
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }

    tags = {
        Name = "pez-cloudfront"
    }
}

output "cloudfront_domain_name" {
    value = aws_cloudfront_distribution.main.domain_name
}

resource "aws_dynamodb_table" "main" {
    name = "pez-dynamodb"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "id"
    attribute {
        name = "id"
        type = "S"
    }
}

data "archive_file" "lambda_archive" {
  type        = "zip"
  source_dir  = "../lambda"
  output_path = "../build/packages/lambda.zip"

  output_file_mode = "0644"
}
resource "aws_lambda_function" "main" {
  function_name     = "dynamodb-get-pez"
  role              = aws_iam_role.iam_for_lambda.arn
  runtime           = "nodejs20.x"
  handler           = "src/index.run"
  source_code_hash  = data.archive_file.lambda_archive.output_base64sha256
}

resource "aws_lambda_permission" "main" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.main.id}/*/*/*"
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "pez-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "main" {
    name = "pez-api"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "items"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
}

resource "aws_api_gateway_integration" "main" {
    rest_api_id = aws_api_gateway_rest_api.main.id
    resource_id = aws_api_gateway_rest_api.main.root_resource_id
    http_method = aws_api_gateway_method.method.http_method

    integration_http_method = "GET"
    type                    = "AWS_PROXY"
    uri                     = aws_lambda_function.main.invoke_arn
}
