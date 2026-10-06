# Instance role: SSM core (Session Manager, no SSH) plus write access to the
# session transcript log group. Nothing else.

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name_prefix        = "${var.name}-app-"
  description        = "SecureVPC app instances: SSM Session Manager only"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "session_logging" {
  statement {
    sid = "SessionTranscripts"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.sessions.arn,
      "${aws_cloudwatch_log_group.sessions.arn}:*",
    ]
  }

  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "session_logging" {
  name   = "session-logging"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.session_logging.json
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.name}-app-"
  role        = aws_iam_role.app.name
}

# Least-privilege policy for human operators (output only; attach it to your
# own role). Sessions are allowed only to this stack's app instances, only
# with the logged/encrypted session document.
data "aws_iam_policy_document" "operator" {
  statement {
    sid       = "StartSessionOnAppInstances"
    actions   = ["ssm:StartSession"]
    resources = ["arn:${var.partition}:ec2:${var.region}:${var.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/AccessTier"
      values   = ["${var.name}-app"]
    }
  }

  statement {
    sid       = "OnlyTheLoggedSessionDocument"
    actions   = ["ssm:StartSession"]
    resources = [aws_ssm_document.session.arn]
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
  }

  statement {
    sid       = "ManageOwnSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:${var.partition}:ssm:${var.region}:${var.account_id}:session/$${aws:userid}-*"]
  }

  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}
