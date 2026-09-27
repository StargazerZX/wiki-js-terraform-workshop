# Wiki.js stores everything in PostgreSQL. This file is ready to apply as-is:
# apply it FIRST, because RDS takes 5-10 minutes to create and we'll write the
# module while it builds.

resource "aws_security_group" "db" {
  name        = "${local.name}-wiki-db"
  description = "Wiki.js database. Who may connect is decided in wiki.tf, next to the service it trusts."
  vpc_id      = data.aws_vpc.workshop.id

  tags = {
    Name = "${local.name}-wiki-db"
  }
}

resource "aws_db_subnet_group" "wiki" {
  name       = "${local.name}-wiki"
  subnet_ids = data.aws_subnets.private.ids
}

# 🏭 Production note — what a real database would add:
#   - backup_retention_period >= 7 and deletion_protection = true (both
#     disabled here so the lab can be torn down in minutes),
#   - Performance Insights and enhanced monitoring,
#   - IAM database authentication for humans, instead of the master user.
#trivy:ignore:AVD-AWS-0077
#trivy:ignore:AVD-AWS-0133
#trivy:ignore:AVD-AWS-0176
#trivy:ignore:AVD-AWS-0177
resource "aws_db_instance" "wiki" {
  identifier     = "${local.name}-wiki"
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "wiki"
  username = "wikijs"

  # RDS generates the master password and keeps it in Secrets Manager.
  # It never appears in this code, in a .tfvars file, or in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.wiki.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true
}
