# Terraform Workshop — Wiki.js on AWS, one module at a time

A two-hour, type-along lab for people who already know Terraform's basics (resources, data
sources, variables, locals, outputs, providers). Together we design and write a reusable
`web-service` module, then use it to deploy **Wiki.js** on ECS Fargate behind a load balancer,
backed by RDS PostgreSQL.

## What's in here

```
lab.md                   Student lab (Read-Do-Verify), one step per slide block
slides.md                Marp deck, presented interleaved with the lab

network/                 The workshop VPC. Presenter applies it once in the shared account;
                         own-account students apply it once in theirs.
starter/wiki/            What students copy: database, cluster, network lookups pre-written;
                         empty modules/web-service/ to type into
solution/wiki/           The finished root, including the module and the break-fix

```

## Versions

| Tool | Version |
|---|---|
| Terraform CLI | `>= 1.10.0, < 2.0.0` (written against 1.16.1) |
| hashicorp/aws provider | `~> 6.58` |
| AWS CLI | v2 |
| Wiki.js image | `ghcr.io/requarks/wiki:2.5.314` |
| RDS engine | PostgreSQL 17 on `db.t4g.micro` |
| Region | `us-east-1` |

## Account models

- **Own AWS account:** apply `network/` once, then follow the lab with your own credentials.
- **Shared workshop user (10–15 people):** the presenter applies hands out one access key and the boundary ARN. Isolation between
  students is by naming (`ws-<handle>-...`), not enforced by IAM.
