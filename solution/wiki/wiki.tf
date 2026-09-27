# Wiki.js, deployed with the web-service module and wired to its database.

locals {
  wiki_environment = {
    DB_TYPE = "postgres"
    DB_HOST = aws_db_instance.wiki.address
    DB_PORT = tostring(aws_db_instance.wiki.port)
    DB_USER = aws_db_instance.wiki.username
    DB_NAME = aws_db_instance.wiki.db_name

    # RDS for PostgreSQL 15+ only accepts encrypted connections. DB_SSL=true
    # would make Wiki.js verify the certificate against Node's built-in CA
    # list, which doesn't include Amazon RDS's CA, so the connection fails.
    # Instead we leave DB_SSL off and let the Postgres driver read PGSSLMODE:
    # "no-verify" = encrypted, certificate not checked.
    # 🏭 Production note: verify the server too — pass the RDS CA certificate
    # in DB_SSL_CA (Wiki.js 2.3+) instead of PGSSLMODE=no-verify.
    DB_SSL    = "false"
    PGSSLMODE = "no-verify"
  }
}

module "wiki" {
  source = "./modules/web-service"

  name           = "${local.name}-wiki"
  image          = var.wiki_image
  container_port = 3000
  tier           = "medium" # Wiki.js asks for at least 1 GB of memory

  environment = local.wiki_environment
  secrets = {
    DB_PASS = {
      secret_arn = aws_db_instance.wiki.master_user_secret[0].secret_arn
      json_key   = "password"
    }
  }

  health_check_path = "/healthz"
  # First boot creates Wiki.js's tables before it answers anything.
  health_check_grace_period_seconds = 180

  cluster_arn = aws_ecs_cluster.this.arn
  vpc_id      = data.aws_vpc.workshop.id
  subnet_ids  = data.aws_subnets.public.ids

  role_permissions_boundary_arn = var.role_permissions_boundary_arn
}

# The database accepts Postgres connections from the Wiki.js tasks only.
resource "aws_vpc_security_group_ingress_rule" "db_from_wiki" {
  security_group_id            = aws_security_group.db.id
  description                  = "Postgres from the Wiki.js tasks"
  referenced_security_group_id = module.wiki.service_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ...and the Wiki.js tasks may open connections to the database. The module
# only allows outbound 443 by default; this is the break-fix from Step 6.
resource "aws_vpc_security_group_egress_rule" "wiki_to_db" {
  security_group_id            = module.wiki.service_security_group_id
  description                  = "Postgres to the Wiki.js database"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
