resource "aws_key_pair" "admin" {
  key_name_prefix = "${var.name}-admin-"
  public_key      = var.ssh_public_key

  tags = { Name = "${var.name}-admin-key" }
}

locals {
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
}

resource "aws_instance" "bastion" {
  #checkov:skip=CKV_AWS_88:The bastion is the single intended public entry point; SG + NACL restrict TCP/22 to admin CIDRs.
  #checkov:skip=CKV_AWS_126:Detailed (1-minute) monitoring is a paid feature; basic monitoring is enough for a lab.
  #checkov:skip=CKV2_AWS_41:No AWS API access is required on the bastion; omitting an instance profile keeps its credentials surface at zero.
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = file("${path.module}/templates/bastion.sh")

  tags        = { Name = "${var.name}-bastion", Role = "bastion" }
  volume_tags = { Name = "${var.name}-bastion-root" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "web" {
  #checkov:skip=CKV_AWS_126:Detailed (1-minute) monitoring is a paid feature; basic monitoring is enough for a lab.
  #checkov:skip=CKV2_AWS_41:No AWS API access is required on the web server; omitting an instance profile keeps its credentials surface at zero.
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.web_sg_id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/web.sh.tftpl", { name = var.name })

  tags        = { Name = "${var.name}-web", Role = "web" }
  volume_tags = { Name = "${var.name}-web-root" }

  lifecycle {
    ignore_changes = [ami]
  }
}
