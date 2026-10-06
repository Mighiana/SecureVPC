# Query the S3 flow log archive with Athena. Partition projection maps the
# Hive-style year/month/day/hour prefixes directly, so there is no crawler and
# no MSCK REPAIR; queries filtered on today only scan today's objects.

locals {
  db_name  = "${replace(lower(var.name), "-", "_")}_flowlogs"
  location = "s3://${var.bucket_name}/AWSLogs/aws-account-id=${var.account_id}/aws-service=vpcflowlogs/aws-region=${var.region}/"

  # Parquet columns use underscores where the flow log field names use hyphens.
  numeric_types = {
    version        = "int"
    srcport        = "int"
    dstport        = "int"
    protocol       = "bigint"
    packets        = "bigint"
    bytes          = "bigint"
    start          = "bigint"
    end            = "bigint"
    "tcp-flags"    = "int"
    "traffic-path" = "int"
  }

  columns = [for f in var.fields : { name = replace(f, "-", "_"), type = lookup(local.numeric_types, f, "string") }]

  today = "year = date_format(current_date, '%Y') AND month = date_format(current_date, '%m') AND day = date_format(current_date, '%d')"
}

resource "aws_glue_catalog_database" "this" {
  name        = local.db_name
  description = "VPC Flow Logs for ${var.name}"
}

resource "aws_glue_catalog_table" "flow_logs" {
  name          = "vpc_flow_logs"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                    = "TRUE"
    classification              = "parquet"
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2025,2100"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "1,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "1,31"
    "projection.day.digits"     = "2"
    "projection.hour.type"      = "integer"
    "projection.hour.range"     = "0,23"
    "projection.hour.digits"    = "2"
    "storage.location.template" = "${local.location}year=$${year}/month=$${month}/day=$${day}/hour=$${hour}"
  }

  dynamic "partition_keys" {
    for_each = ["year", "month", "day", "hour"]
    content {
      name = partition_keys.value
      type = "string"
    }
  }

  storage_descriptor {
    location      = local.location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}

resource "aws_athena_workgroup" "this" {
  name          = "${var.name}-flow-logs"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = var.kms_key_arn == null ? "SSE_S3" : "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }
}

resource "aws_athena_named_query" "rejected_today" {
  name      = "${var.name}/rejected-today"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.this.name
  query     = <<-EOT
    SELECT srcaddr, dstaddr, dstport, protocol, count(*) AS rejected
    FROM vpc_flow_logs
    WHERE action = 'REJECT' AND ${local.today}
    GROUP BY srcaddr, dstaddr, dstport, protocol
    ORDER BY rejected DESC
    LIMIT 50
  EOT
}

resource "aws_athena_named_query" "egress_destinations_today" {
  name      = "${var.name}/egress-destinations-today"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.this.name
  query     = <<-EOT
    SELECT pkt_dstaddr, dstport, pkt_dst_aws_service, traffic_path, sum(bytes) AS bytes
    FROM vpc_flow_logs
    WHERE flow_direction = 'egress' AND action = 'ACCEPT' AND ${local.today}
    GROUP BY pkt_dstaddr, dstport, pkt_dst_aws_service, traffic_path
    ORDER BY bytes DESC
    LIMIT 50
  EOT
}

resource "aws_athena_named_query" "traffic_paths_today" {
  name      = "${var.name}/traffic-paths-today"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.this.name
  query     = <<-EOT
    SELECT subnet_id, flow_direction, traffic_path, action, count(*) AS flows, sum(bytes) AS bytes
    FROM vpc_flow_logs
    WHERE ${local.today}
    GROUP BY subnet_id, flow_direction, traffic_path, action
    ORDER BY bytes DESC
  EOT
}
