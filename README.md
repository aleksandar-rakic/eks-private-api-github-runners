# Private EKS API with in-cluster GitHub runners

[![ci](https://github.com/aleksandar-rakic/eks-private-api-github-runners/actions/workflows/ci.yml/badge.svg)](https://github.com/aleksandar-rakic/eks-private-api-github-runners/actions/workflows/ci.yml)

How to take an EKS cluster's Kubernetes API off the internet without breaking CI: split the pipeline by what each job needs to reach, and run the Kubernetes half inside the cluster.

## The problem

Making the API endpoint private is one setting. The trouble is everything that quietly depended on the public endpoint. CI is the usual one: GitHub-hosted runners live on the internet, so once the endpoint goes private, every job that runs `kubectl` or `helm` can no longer reach the cluster. The jobs do not fail. They hang until they time out.

I ran into exactly that on a production platform: the endpoint went private before the in-cluster runners existed, and the change had to be reverted until the pieces below were in place. This repository is the order of operations I would use from the start.

## Design

```
                     GitHub
          ┌────────────────────────────┐
          │ hosted runners             │──── OIDC ────▶ IAM role ──▶ AWS APIs
          │ terraform/foundations      │               (VPC, EKS, IAM)
          └────────────────────────────┘
                        │
                        │  job queue (outbound HTTPS from the cluster)
                        ▼
   ┌────────────────── VPC ─────────────────────────────────────┐
   │  EKS, private endpoint                                     │
   │  ┌──────────────────────────────────┐                      │
   │  │ arc-platform runners (ARC)       │──▶ Kubernetes API     │
   │  │ kubernetes/platform              │    (private)          │
   │  └──────────────────────────────────┘                      │
   └────────────────────────────────────────────────────────────┘
```

| Job needs | Runs on | Identity |
|---|---|---|
| AWS APIs only: VPC, EKS control plane, node groups, IAM | GitHub-hosted runner | IAM role through GitHub OIDC, no stored keys |
| Kubernetes API: CRDs, namespaces, Helm releases | `arc-platform` runners inside the cluster | Kubernetes ServiceAccount |

The runners connect out to GitHub to pick up jobs, so nothing inbound is opened. Engineers reach the private endpoint through the VPC (Client VPN, a zero-trust client, or SSM port forwarding), not through a public endpoint.

## What is in the repository

```
terraform/foundations/   VPC, EKS with a private endpoint, access entries, GitHub OIDC roles
kubernetes/arc/          Actions Runner Controller values and the runner ServiceAccount
kubernetes/platform/     example of what the in-cluster runners apply
.github/workflows/       foundations (hosted), platform (in-cluster), ci (fmt, validate, lint)
```

Choices worth pointing out:

- **Two OIDC roles.** Pull requests get a read-only plan role. Only the protected `foundations` environment can assume the apply role, so a branch cannot apply.
- **Access entries, not `aws-auth`.** `authentication_mode = "API"` and no automatic admin for whoever ran `terraform apply`. Cluster admins are listed explicitly, usually SSO permission-set roles.
- **Runner credentials stay out of Helm values.** The GitHub App key goes into a Kubernetes Secret created out of band. In Helm values it would show up in plan output and in the release history.
- **IMDSv2 required on nodes**, with a hop limit of 1 so pods cannot reach the node's instance credentials.
- **S3 gateway endpoint**, so image layers and other S3 traffic do not go through the NAT gateway.

## Bootstrap: the chicken and the egg

A brand-new cluster has no runners, and with a private endpoint nothing outside the VPC can install them. The foundations stack handles that with an explicit, short window:

1. Apply with `bootstrap_public_endpoint = true` and `bootstrap_cidrs` set to the operator's address. The variable refuses `0.0.0.0/0`.
2. From that address, install the controller and the runner scale set:
   ```bash
   kubectl create namespace arc-runners
   kubectl create secret generic arc-github-app -n arc-runners \
     --from-literal=github_app_id=... \
     --from-literal=github_app_installation_id=... \
     --from-file=github_app_private_key=app.pem
   kubectl apply -f kubernetes/arc/runner-rbac.yaml
   helm install arc oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
     -n arc-systems --create-namespace -f kubernetes/arc/controller-values.yaml
   helm install arc-platform oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
     -n arc-runners -f kubernetes/arc/runner-scale-set-values.yaml
   ```
3. Check that `arc-platform` shows up under the repository's runners.
4. Apply again with `bootstrap_public_endpoint = false`. From here on, nothing needs the public endpoint.

## Usage

```bash
cd terraform/foundations
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init \
  -backend-config="bucket=<state bucket>" \
  -backend-config="key=foundations.tfstate" \
  -backend-config="region=eu-central-1"
terraform plan
```

Repository variables used by the workflows: `TF_STATE_BUCKET`, `FOUNDATIONS_PLAN_ROLE_ARN`, `FOUNDATIONS_APPLY_ROLE_ARN`, and `ARC_RUNNERS_READY` set to `true` once the runners are registered. Until they are set, the foundations and platform workflows skip instead of failing or waiting. Create a `foundations` environment restricted to `main`.

## Scope

This is a reference implementation written for this repository in plain Terraform, based on a setup I ran in production in CDKTF (TypeScript). CI checks formatting, `terraform validate`, the Kubernetes manifests and the workflows; it does not deploy anything. Before using it for real:

- narrow `apply_policy_arns` from `AdministratorAccess` to what the stack creates,
- decide whether the platform runners need `cluster-admin` or a narrower role.

## License

MIT
