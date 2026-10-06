resource "aws_cloudwatch_log_group" "sessions" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; the default keeps a lab cheap.
  name              = var.session_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# Session preferences: every session is KMS-encrypted end to end and its
# transcript streamed to CloudWatch. Use with --document-name.
resource "aws_ssm_document" "session" {
  name            = "${var.name}-session-preferences"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "SecureVPC session preferences: encrypted, logged, time-limited"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = element(split("/", var.kms_key_arn), 1)
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile                = { linux = "", windows = "" }
    }
  })
}
