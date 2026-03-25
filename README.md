# AI Digital Twin on AWS

> A production-grade AI chatbot that represents *you* — powered by AWS Bedrock, deployed serverlessly, and built with modern web technologies.

[![Deploy](https://github.com/actions/workflows/deploy.yml/badge.svg)](../../actions/workflows/deploy.yml)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](terraform/)
[![Next.js](https://img.shields.io/badge/Frontend-Next.js%2016-black?logo=next.js)](frontend/)
[![Python](https://img.shields.io/badge/Backend-Python%203.13-3776AB?logo=python)](backend/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws)](terraform/main.tf)

**Live:** [kausik-digital-twin.com](https://kausik-digital-twin.com)

---

## What Is This?

This project builds a **Digital Twin** — an AI that knows who you are and can have conversations on your behalf. You feed it your resume, a personal bio, communication style notes, and key facts. It becomes a conversational version of you, hosted globally on AWS.

Built across 5 days as a structured learning project covering frontend, backend, cloud infrastructure, and DevOps.

---

## Architecture

```
                        ┌──────────────────┐
                        │   User Browser   │
                        └────────┬─────────┘
                                 │ HTTPS
                        ┌────────▼─────────┐
                        │   CloudFront     │  ← Global CDN, HTTPS, caching
                        └────────┬─────────┘
                 ┌───────────────┴───────────────┐
                 │                               │
        ┌────────▼─────────┐           ┌─────────▼────────┐
        │  S3 Static Site  │           │   API Gateway    │  ← CORS, throttling
        │  (Next.js build) │           └─────────┬────────┘
        └──────────────────┘                     │ invoke
                                        ┌────────▼─────────┐
                                        │  AWS Lambda      │  ← Python 3.13, FastAPI
                                        │  (FastAPI/Mangum) │
                                        └────────┬─────────┘
                                  ┌─────────────┴─────────────┐
                                  │                           │
                         ┌────────▼────────┐        ┌────────▼────────┐
                         │  AWS Bedrock    │        │  S3 Memory      │
                         │  (Nova models)  │        │  (Conversations) │
                         └─────────────────┘        └─────────────────┘

                    Optional: Route53 + ACM for custom domain
```

### Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 16, React 19, TypeScript, Tailwind CSS v4 |
| Backend | FastAPI, Python 3.13, Mangum (Lambda adapter) |
| AI | AWS Bedrock — Amazon Nova (Micro / Lite / Pro) |
| Compute | AWS Lambda (serverless) |
| API | AWS API Gateway (HTTP API) |
| Storage | S3 — static hosting + conversation memory |
| CDN | AWS CloudFront |
| DNS / SSL | Route53 + ACM (optional custom domain) |
| IaC | Terraform with S3 remote state |
| CI/CD | GitHub Actions with OIDC authentication |

---

## Project Structure

```
digital-twin-aws/
├── frontend/               # Next.js app (static export → S3)
│   ├── app/
│   │   ├── page.tsx        # Home page
│   │   └── layout.tsx      # Root layout
│   └── components/
│       └── twin.tsx        # Chat interface component
│
├── backend/                # FastAPI backend (→ Lambda)
│   ├── server.py           # API routes and Bedrock integration
│   ├── lambda_handler.py   # Lambda entry point (Mangum)
│   ├── context.py          # System prompt builder
│   ├── resources.py        # Personal data loader
│   ├── deploy.py           # Lambda package builder
│   └── data/               # Your personal data
│       ├── facts.json      # Key facts about you
│       ├── linkedin.pdf    # LinkedIn resume
│       ├── summary.txt     # Personal summary
│       └── style.txt       # Communication style
│
├── terraform/              # Infrastructure as Code
│   ├── main.tf             # All AWS resources
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   ├── backend.tf          # S3 remote state
│   └── versions.tf         # Provider versions
│
├── scripts/
│   ├── deploy.sh           # Full deploy (Lambda + Terraform)
│   └── destroy.sh          # Teardown environment
│
├── .github/workflows/
│   ├── deploy.yml          # CI/CD: push to main → deploy
│   └── destroy.yml         # Manual environment teardown
│
└── week2/                  # Course materials (Day 1–5)
```

---

## Getting Started

### Prerequisites

- AWS account with appropriate permissions
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [uv](https://github.com/astral-sh/uv) (Python package manager)
- Node.js 20+
- Docker (for Lambda package builds)

### 1. Clone and configure

```bash
git clone https://github.com/your-username/digital-twin-aws
cd digital-twin-aws
cp .env.example .env
```

Edit `.env`:
```env
AWS_ACCOUNT_ID=123456789012
DEFAULT_AWS_REGION=us-east-1
PROJECT_NAME=twin
```

### 2. Add your personal data

```bash
# Edit these files with your information
backend/data/facts.json     # Name, job, skills, hobbies, etc.
backend/data/summary.txt    # A paragraph about yourself
backend/data/style.txt      # How you communicate
backend/data/linkedin.pdf   # Your resume (optional)
```

### 3. Deploy

```bash
# Deploy to dev environment
./scripts/deploy.sh dev

# Or deploy to prod
./scripts/deploy.sh prod
```

The script will:
1. Build the Lambda deployment package
2. Initialize Terraform with S3 remote state
3. Create/switch to the appropriate workspace
4. Apply all infrastructure changes
5. Upload the Next.js build to S3
6. Invalidate the CloudFront cache

---

## CI/CD

Push to `main` automatically triggers a full deployment to AWS via GitHub Actions.

**Required GitHub Secrets:**

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `DEFAULT_AWS_REGION` | Target region (e.g. `us-east-1`) |

**Workflows:**

- **`deploy.yml`** — Triggered on push to `main` or manual dispatch. Selectable environment (dev/test/prod).
- **`destroy.yml`** — Manual only. Requires typing the environment name as confirmation to prevent accidents.

Authentication uses **OIDC** — no long-lived AWS credentials stored in GitHub.

---

## Multi-Environment Support

Terraform workspaces map to separate environments with isolated state:

```
dev   → twin-dev-lambda,  twin-dev-api,  twin-dev-cloudfront,  ...
test  → twin-test-lambda, twin-test-api, ...
prod  → twin-prod-lambda, twin-prod-api, ... (+ optional custom domain)
```

---

## Configuration

Key Terraform variables ([`terraform/variables.tf`](terraform/variables.tf)):

| Variable | Default | Description |
|---|---|---|
| `bedrock_model_id` | `us.amazon.nova-lite-v1:0` | Bedrock model to use |
| `lambda_timeout` | `60` | Lambda timeout in seconds |
| `api_throttle_rate_limit` | `5` | Requests per second |
| `api_throttle_burst_limit` | `10` | Burst request limit |
| `use_custom_domain` | `false` | Enable custom domain + SSL |
| `root_domain` | `""` | Your domain (e.g. `example.com`) |

**Model options** (AWS Bedrock Nova family):

| Model | Speed | Cost | Use Case |
|---|---|---|---|
| `amazon.nova-micro-v1:0` | Fastest | Cheapest | High-volume, simple responses |
| `us.amazon.nova-lite-v1:0` | Balanced | Moderate | Default — good quality/cost ratio |
| `us.amazon.nova-pro-v1:0` | Slower | Higher | Complex reasoning |

---

## How the Twin Works

1. **You provide personal data** — facts, bio, LinkedIn, communication style
2. **Each chat request** loads your data and builds a detailed system prompt
3. **Conversation history** is stored in S3 (keyed by session ID)
4. **The Lambda** retrieves history, prepends your context, sends to Bedrock, saves the response
5. **The frontend** maintains a session ID across the browser session

The twin is instructed never to hallucinate facts and to deflect jailbreak attempts — it only knows what you've told it.

---

## Week 2 — Learning Path

This project was built day-by-day as part of a structured course:

| Day | Topic | What You Build |
|---|---|---|
| [Day 1](week2/day1.md) | Local Digital Twin | Next.js chat UI + FastAPI backend with memory |
| [Day 2](week2/day2.md) | Deploy to AWS | Lambda + API Gateway + S3 + CloudFront |
| [Day 3](week2/day3.md) | AWS Bedrock | Swap OpenAI for Amazon Nova models |
| [Day 4](week2/day4.md) | Terraform IaC | Replace manual setup with reproducible infrastructure |
| [Day 5](week2/day5.md) | CI/CD | GitHub Actions with OIDC, remote state, auto-deploy |

---

## Tear Down

```bash
# Destroy a specific environment
./scripts/destroy.sh dev

# Or use the GitHub Actions workflow (safer — requires confirmation)
# Actions → destroy.yml → Run workflow → type environment name
```

---

## License

[MIT](LICENSE)
