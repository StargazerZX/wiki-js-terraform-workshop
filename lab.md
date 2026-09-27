# Terraform Workshop — Wiki.js on AWS, one module at a time

**Time:** 2 hours. The slides are presented as we go: your presenter introduces each step just
before you do it.

**What you'll have at the end:** your own Wiki.js — a real web app with a real PostgreSQL
database — running on AWS behind a load balancer, deployed by Terraform, using a reusable module
you wrote yourself.

```
            ┌────────────── your Terraform ───────────────┐
 browser ──▶│ ALB ──▶ ECS Fargate task (Wiki.js) ──▶ RDS  │
            │          └─ module "wiki" (web-service) ─┘  │
            └──────────────────────────────────────────────┘
                 inside the workshop VPC (already created)
```

**What we assume you know** (from the course): resource and data blocks, variables, locals,
outputs, providers, `init`/`plan`/`apply`/`destroy`.

**What's new today:** designing and writing a module, and the functions and expressions that
make one pleasant to use.

**Tools:** Terraform 1.10 or newer (written against 1.16.1), AWS CLI v2, a browser, and a code
editor. No Docker needed.

---

## Start here (⏱ ~7 min)

**1. Get the code.** From wherever you put the workshop repository:

```bash
export WORKSHOP_REPO="$(pwd)"
export AWS_DEFAULT_REGION=us-east-1
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR" ~/workshop
cp -r "$WORKSHOP_REPO/starter/wiki" ~/workshop/wiki
cd ~/workshop/wiki
```

`AWS_DEFAULT_REGION` makes the AWS CLI commands in this lab look in the same region as
Terraform. `TF_PLUGIN_CACHE_DIR` means the AWS provider (a few hundred MB) is downloaded once, not
once per directory — 15 people share this Wi-Fi.

**2. Credentials.** Pick the one that applies to you.

> 🅿 **Own AWS account:** make sure `aws sts get-caller-identity` works with the credentials
> Terraform will use. Then create the workshop network in your account (about a minute; nothing
> in it is billed by the hour):
> ```bash
> cd "$WORKSHOP_REPO/network"
> terraform init
> terraform apply
> cd ~/workshop/wiki
> ```
>
> 🅢 **Shared workshop user:** your presenter gives you an access key ID and secret. Store them
> in their own profile and switch to it:
> ```bash
> aws configure --profile tf-workshop
> # Access key ID / Secret access key: from your presenter
> # Default region name: us-east-1
> # Default output format: json
> export AWS_PROFILE=tf-workshop
> ```
> If you already have AWS keys in environment variables, they win over `AWS_PROFILE`. Clear them
> for this terminal: `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`.

**VERIFICATION:**

```bash
aws sts get-caller-identity --query Arn --output text
```

Expected output (🅢 shown; 🅿 shows your own user or role):

```
arn:aws:iam::<account-id>:user/ws-shared-student
```

**3. Your settings.** Create `terraform.tfvars` in `~/workshop/wiki`. Pick a short handle that
nobody else in the room will pick — every resource you create starts with `ws-<handle>`:

```hcl
student = "<yourhandle>"
```

> 🅢 **Shared workshop user:** also add the boundary line your presenter gives you:
> ```hcl
> role_permissions_boundary_arn = "arn:aws:iam::<account-id>:policy/ws-role-boundary"
> ```

---

## Step 1: Start the database first (⏱ ~5 min, then it builds on its own)

**CONCEPT:** A managed PostgreSQL database takes 5–10 minutes to create, so we start it now and
write the module while it builds. `database.tf` and `cluster.tf` are already written — read them
while `init` runs; note that nobody ever types the database password.

**ACTION:**

```bash
terraform init
terraform apply
```

Check the plan, type `yes`, and **leave this terminal running**. Open your editor (and a second
terminal) for the next steps.

**VERIFICATION:** open a **second terminal** and set it up the same way — a new terminal doesn't
inherit the first one's variables. Use this second terminal for everything from here on:

```bash
cd ~/workshop/wiki
export WORKSHOP_REPO="<path to the workshop repo>"   # the same path as in Start here
export AWS_DEFAULT_REGION=us-east-1
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
export AWS_PROFILE=tf-workshop                        # 🅢 shared workshop user only
```

```bash
aws rds describe-db-instances --db-instance-identifier ws-<yourhandle>-wiki \
  --query 'DBInstances[0].DBInstanceStatus' --output text
```

Expected output (it moves on to `backing-up` or `available` later):

```
creating
```

The plan you approved ended with:

```
Plan: 4 to add, 0 to change, 0 to destroy.
```

---

## Step 2: Design the module's interface (⏱ ~10 min — type along)

**CONCEPT:** A module is a promise: *give me these inputs, I'll give you a running web service and
these outputs.* We write that promise first — `variables.tf` — before a single resource, because
the interface is what everyone who uses the module has to live with.

**ACTION:** Create the module's first two files. Type along with the presenter; the comments are
for you to read, not to type.

`modules/web-service/versions.tf`:

```hcl
# A module states the MINIMUM versions it works with. The root that calls it
# pins exact versions. No provider block: the module uses the caller's.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
```

`modules/web-service/variables.tf`:

```hcl
# ---- What the service is ----------------------------------------------------

variable "name" {
  description = "Name for every resource this module creates, e.g. \"ws-alice-wiki\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,28}$", var.name))
    error_message = "name must be 1-28 lowercase letters, digits or hyphens (load balancer and target group names are capped at 32, and we append a suffix)."
  }
}

variable "image" {
  description = "Container image, including the tag."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
}

variable "tier" {
  description = "Size preset: small (0.25 vCPU / 0.5 GB), medium (0.5 vCPU / 1 GB) or large (1 vCPU / 2 GB)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.tier)
    error_message = "tier must be one of: small, medium, large."
  }
}

variable "desired_count" {
  description = "How many copies of the container to run."
  type        = number
  default     = 1
}

variable "environment" {
  description = "Plain environment variables, as NAME => value. Never secrets: these are visible in the task definition."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables, as NAME => { secret_arn, json_key }. ECS reads them from Secrets Manager when the container starts."
  type = map(object({
    secret_arn = string
    json_key   = optional(string)
  }))
  default = {}
}

variable "health_check_path" {
  description = "Path the load balancer calls to decide whether a container is healthy."
  type        = string
  default     = "/"
}

variable "health_check_grace_period_seconds" {
  description = "How long ECS ignores failed health checks after a container starts. Raise it for slow-starting apps."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Extra tags for every resource this module creates."
  type        = map(string)
  default     = {}
}

# ---- Where it runs ------------------------------------------------------------

variable "cluster_arn" {
  description = "ECS cluster to run the service in."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the load balancer and the service."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets for the load balancer and the tasks. At least two, in different availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Application Load Balancer needs at least two subnets."
  }
}

variable "role_permissions_boundary_arn" {
  description = "Permissions boundary for the task execution role. Empty means none."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps the container logs."
  type        = number
  default     = 7
}
```

> ⚠️ **Fell behind?** Copy the file and catch up at the next step:
> `cp "$WORKSHOP_REPO/solution/wiki/modules/web-service/variables.tf" modules/web-service/`

**VERIFICATION:** a module can be checked on its own, without touching any state. Install the
provider for the module directory once, then validate it:

```bash
terraform -chdir=modules/web-service init -backend=false
terraform -chdir=modules/web-service validate
```

Expected output (last line):

```
Success! The configuration is valid.
```

---

## Step 3: The service itself (⏱ ~13 min — type along)

**CONCEPT:** Inside the module, `locals` turn the friendly interface into what AWS actually wants:
a size preset into CPU and memory, maps into the list-of-objects shape ECS expects, and secret
references into ECS's `arn:json-key::` syntax. The resources then only ever read those locals, so
each one stays short.

**ACTION:**

`modules/web-service/main.tf`:

```hcl
data "aws_region" "current" {}

locals {
  # Callers pick a size, not raw numbers. Every pair here is a valid Fargate
  # CPU/memory combination, so a caller can't ask for one that isn't.
  tiers = {
    small  = { cpu = 256, memory = 512 }
    medium = { cpu = 512, memory = 1024 }
    large  = { cpu = 1024, memory = 2048 }
  }
  size = local.tiers[var.tier]

  # Maps in the interface, lists for ECS. A `for` over a map runs in sorted
  # key order, so the task definition (and the plan) is stable.
  container_environment = [
    for name, value in var.environment : { name = name, value = value }
  ]

  # ECS syntax for "one JSON key of a secret" is <secret-arn>:<json-key>::
  # The module knows that syntax so callers don't have to.
  container_secrets = [
    for name, secret in var.secrets : {
      name      = name
      valueFrom = secret.json_key == null ? secret.secret_arn : "${secret.secret_arn}:${secret.json_key}::"
    }
  ]

  # Several env vars can come from one secret; IAM needs each secret once.
  secret_arns = distinct([for secret in values(var.secrets) : secret.secret_arn])
}

# 🏭 Production note: encrypt log groups with a customer-managed KMS key.
#trivy:ignore:AVD-AWS-0017
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.size.cpu
  memory                   = local.size.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.image
      essential    = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment  = local.container_environment
      secrets      = local.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # public subnets, no NAT gateway: needed to pull the image
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # The target group only accepts targets once the listener points at it, and
  # the first task can only start once its role may write logs and read secrets.
  depends_on = [aws_lb_listener.http, aws_iam_role_policy.execution]

  tags = var.tags
}
```

`modules/web-service/iam.tf`:

```hcl
# The EXECUTION role is what ECS itself uses to start the container: write its
# logs, and read its secrets. (A separate TASK role would be what the app's own
# code uses to call AWS. Wiki.js doesn't call AWS, so there isn't one.)

data "aws_iam_policy_document" "assume_by_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name                 = "${var.name}-exec"
  assume_role_policy   = data.aws_iam_policy_document.assume_by_ecs_tasks.json
  permissions_boundary = var.role_permissions_boundary_arn == "" ? null : var.role_permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  # Only when the caller passed secrets: a statement with an empty resource
  # list is invalid, so this block exists zero or one times.
  dynamic "statement" {
    for_each = length(local.secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadOwnSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = local.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name}-exec"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}
```

> ⚠️ **Fell behind?**
> `cp "$WORKSHOP_REPO/solution/wiki/modules/web-service/"{main,iam}.tf modules/web-service/`

**VERIFICATION:**

```bash
terraform -chdir=modules/web-service validate
```

Expected: it **fails**, and that's the point. Every error is `Reference to undeclared resource`,
and they name only things the next step creates — `aws_security_group.service`,
`aws_lb_target_group.this` and `aws_lb_listener.http`. Any *other* error is a typo to fix now.

---

## Step 4: Traffic in, traffic out (⏱ ~10 min — type along)

**CONCEPT:** Two security groups form a chain: the internet may reach the load balancer, and only
the load balancer may reach the tasks. The tasks themselves may only call out on port 443 —
enough to pull their image, write logs and read their secrets.

**ACTION:**

`modules/web-service/network.tf`:

```hcl
# internet --80--> [ALB SG] --container_port--> [service SG] --443--> internet
#
# The service accepts traffic ONLY from its own load balancer, and by default
# may only call out on 443 (to pull its image, write logs, read secrets).

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_security_group" "service" {
  name        = "${var.name}-service"
  description = "Tasks of ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-service" })
}

# A public website: the load balancer accepts the whole internet on port 80.
#trivy:ignore:AVD-AWS-0107
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To the tasks, on the container port"
  referenced_security_group_id = aws_security_group.service.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "From this service's load balancer only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# 🏭 Production note: with private subnets and VPC endpoints for ECR, Logs and
# Secrets Manager, this rule could point at the endpoints instead of the
# internet.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "service_https" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS out: image pull, logs, secrets"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# 🏭 Production note: a public ALB is the point of a website. What production
# adds is HTTPS (an ACM certificate on a 443 listener) and a WAF in front.
#trivy:ignore:AVD-AWS-0053
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = "${var.name}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # Fargate tasks register by IP address
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# 🏭 Production note: no domain name and no certificate in a classroom, so
# plain HTTP. Production listens on 443 and redirects 80 to it.
#trivy:ignore:AVD-AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}
```

`modules/web-service/outputs.tf`:

```hcl
output "url" {
  description = "Where the service answers."
  value       = "http://${aws_lb.this.dns_name}"
}

output "service_security_group_id" {
  description = "Security group of the tasks. Add rules to it for anything the service must reach (e.g. a database)."
  value       = aws_security_group.service.id
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "log_group_name" {
  description = "CloudWatch log group with the container logs."
  value       = aws_cloudwatch_log_group.this.name
}
```

> ⚠️ **Fell behind?**
> `cp "$WORKSHOP_REPO/solution/wiki/modules/web-service/"{network,outputs}.tf modules/web-service/`

**VERIFICATION:**

```bash
terraform -chdir=modules/web-service validate
terraform fmt -recursive
```

Expected output of the first command:

```
Success! The configuration is valid.
```

`fmt` prints the name of any file it had to reformat, or nothing.

---

## Step 5: Deploy Wiki.js with your module (⏱ ~10 min)

**CONCEPT:** Calling a module is the payoff: about twenty lines describe a whole web service, and
everything specific to Wiki.js — its port, its size, its database settings — is an *input*, not
something buried inside the module. The database password reaches the container as a secret
reference; its value never passes through Terraform.

**ACTION:** Your database must be ready first. In the **first** terminal, the Step 1 apply should
have finished with `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` If it's still
running, wait for it. Then carry on in the second terminal.

Create `wiki.tf` in `~/workshop/wiki`:

```hcl
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
```

Create `outputs.tf`:

```hcl
output "wiki_url" {
  description = "Open this in a browser."
  value       = module.wiki.url
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = module.wiki.service_name
}

output "log_group_name" {
  value = module.wiki.log_group_name
}
```

A new module has to be installed before Terraform can use it:

```bash
terraform init
terraform apply
```

Expected plan summary:

```
Plan: 15 to add, 0 to change, 0 to destroy.
```

Type `yes`. The load balancer takes 2–3 minutes.

**VERIFICATION:** give the tasks a minute or two after the apply finishes, then:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$(terraform output -raw wiki_url)"
```

Expected output: you *want* `200`. Read on.

---

## Step 6: It doesn't work (⏱ ~15 min)

> 💥 **Break-Fix BF-1: The wiki never comes up**
> **Symptom:** after several minutes, `curl` still prints `502` or `503`, and the browser shows
> `502 Bad Gateway` or `503 Service Temporarily Unavailable` at the wiki URL.
> **Hint 1:** either code from a load balancer means "I have no working target". Don't guess
> why — ask the container. Its logs are in CloudWatch:
> ```bash
> aws logs tail "$(terraform output -raw log_group_name)" --since 15m
> ```
> **Hint 2:** Wiki.js times out trying to reach its database. (If the message says the
> connection pool is "probably full", ignore that part — it's what a timeout looks like from
> inside.) The task definition's `DB_HOST` and `DB_PORT` say where it's trying to go. Walk the
> path a packet takes from the task to that port: which security group rules does it have to
> pass, **leaving** and **arriving**? Your `wiki.tf` opened one of those two doors.

**ACTION:** Work it out before you open the answer.

<details>
<summary>The fix (open only after you've found it)</summary>

Add the missing rule to the end of `wiki.tf`:

```hcl
# The Wiki.js tasks may open connections to the database. The module
# only allows outbound 443 by default, so the caller grants this.
resource "aws_vpc_security_group_egress_rule" "wiki_to_db" {
  security_group_id            = module.wiki.service_security_group_id
  description                  = "Postgres to the Wiki.js database"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
```

</details>

```bash
terraform apply
```

Expected plan summary:

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

The service has been retrying and backing off; ask it to start fresh containers now instead of
waiting:

```bash
aws ecs update-service --cluster "$(terraform output -raw cluster_name)" \
  --service "$(terraform output -raw service_name)" --force-new-deployment \
  --query 'service.serviceName' --output text
```

**VERIFICATION:** after 1–2 minutes:

```bash
aws logs tail "$(terraform output -raw log_group_name)" --since 5m | grep -i database
curl -s -o /dev/null -w "%{http_code}\n" "$(terraform output -raw wiki_url)"
```

Expected output: a log line containing `Database Connection Successful`, then:

```
200
```

---

## Step 7: Use it, then change it (⏱ ~10 min)

**CONCEPT:** Open your wiki and finish its setup — that data now lives in your RDS database. Then
change one module input and read the plan carefully: some changes update a resource in place,
others replace it, and the plan always tells you which.

**ACTION:** open the URL in your browser:

```bash
terraform output -raw wiki_url
```

Complete the setup page (admin email, a password, and the **Site URL** — paste the same URL).
Log in and create a page.

Now, in `wiki.tf`, change the module's `tier` from `"medium"` to `"large"` and **only plan**:

```bash
terraform plan
```

**VERIFICATION:** expected summary:

```
Plan: 1 to add, 1 to change, 1 to destroy.
```

The task definition is **replaced** (every change registers a new revision) and the service is
**updated in place** to point at it — ECS then rolls your containers over. Your wiki page
survives either way: it lives in the database, not in the container. Change `tier` back to
`"medium"` — no need to apply.

---

## Common Unplanned Failures

| Symptom / Error | Likely Cause | Fix |
|---|---|---|
| `Error: Module not installed` | `terraform init` wasn't re-run after adding the `module` block | `terraform init` |
| `no matching EC2 VPC found` | 🅿: the workshop network wasn't created in your account, or it's in a different region | Run the `network/` apply from "Start here" |
| `AccessDenied` on `iam:CreateRole` (🅢) | `role_permissions_boundary_arn` is missing from `terraform.tfvars` | Add it, re-apply |
| `already exists` for a load balancer, role or DB | Someone else picked the same handle | Pick another `student` value, re-apply |
| `Error acquiring the state lock` | Two `terraform` commands at once in the same directory | Let the first finish; don't run `plan` while Step 1's `apply` is still going |
| Tasks keep stopping before any log appears | The execution role can't read the secret or write logs. See why: `aws ecs describe-services --cluster "$(terraform output -raw cluster_name)" --services "$(terraform output -raw service_name)" --query 'services[0].events[:5].message'` | Compare `iam.tf` with the solution; a single failure right after the first apply heals itself once the role's policy exists |
| Wiki.js logs a database error mentioning SSL, certificates or `pg_hba.conf` | Database TLS settings | Check the `DB_SSL` and `PGSSLMODE` lines in `wiki.tf` match the lab exactly |
| The browser redirects somewhere odd after setup | The Site URL on the setup page doesn't match your wiki URL | Log in and fix it under Administration → General |

## Teardown (⏱ ~10 min, mostly waiting)

```bash
cd ~/workshop/wiki
terraform destroy
```

Expected output (last line; the database takes several minutes to delete):

```
Destroy complete! Resources: 20 destroyed.
```

> 🅿 **Own AWS account:** then remove the workshop network too:
> ```bash
> cd "$WORKSHOP_REPO/network"
> terraform destroy
> ```

**VERIFICATION:**

```bash
aws resourcegroupstaggingapi get-resources --tag-filters Key=Owner,Values=<yourhandle> \
  --query 'ResourceTagMappingList[].ResourceARN'
```

Expected output: `[]`, or only `task-definition/...` ARNs — those are the old revisions ECS keeps
as `INACTIVE`, and they cost nothing.

## Going further (at home)

- Move this root's state to S3 with `use_lockfile = true`, so it isn't only on your laptop.
- Replace `PGSSLMODE=no-verify` with a verified connection: put the RDS CA certificate in
  `DB_SSL_CA`.
- Add HTTPS: an ACM certificate, a 443 listener, and a redirect from 80.
- Move the tasks to private subnets behind a NAT gateway or VPC endpoints.
- Version the module: move it to its own Git repository, tag it, and call it with
  `source = "git::https://...//web-service?ref=v1.0.0"`.
