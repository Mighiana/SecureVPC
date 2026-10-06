output "database_name" {
  description = "Glue database holding the flow log table."
  value       = aws_glue_catalog_database.this.name
}

output "table_name" {
  description = "Glue table over the Parquet flow logs."
  value       = aws_glue_catalog_table.flow_logs.name
}

output "workgroup_name" {
  description = "Athena workgroup (encrypted results, per-query scan limit)."
  value       = aws_athena_workgroup.this.name
}

output "named_queries" {
  description = "Saved Athena queries."
  value = [
    aws_athena_named_query.rejected_today.name,
    aws_athena_named_query.egress_destinations_today.name,
    aws_athena_named_query.traffic_paths_today.name,
  ]
}
