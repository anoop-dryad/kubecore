#!/usr/bin/env just --justfile
# ═════════════════════════════════════════════════════════════════════════════
# kubecore — Justfile (task runner)
#
# `just` is a command runner — like Make but designed for tasks rather than
# build dependencies. Cleaner syntax, better errors. Install: brew install just
#
# This justfile encodes how Terraform should be run for each environment.
# It exists because:
#   1. Multi-env Terraform requires a lot of CLI flags. Easy to forget one.
#   2. Encoding it in code means consistency across team + CI/CD.
#   3. Documents the workflow as runnable commands.
#
# Discover available recipes:
#   just --list
#
# Pattern:
#   - Recipes prefixed with `_` are internal (not meant to be called directly)
#   - Public recipes follow the pattern `tf-<verb>-<env>` e.g. `tf-plan-dev`
#   - Internal `_<verb> target` recipes do the actual work, parameterized by env
#
# How env separation works:
#   - backend.tf has NO `key` line (partial backend config)
#   - At init time, we pass `-backend-config="key=<env>/kubecore"` to set the
#     state file location: s3://<bucket>/<env>/kubecore
#   - We also pass `-var-file=<env>.tfvars` so each env uses its own variables
#   - Switching envs requires `just init-<other-env>` to re-init (intentional)
#
# Why the sha224sum check:
#   Terraform requires `terraform init` to be re-run when:
#     - You switch envs (different backend config)
#     - Providers change versions (lock file updates)
#   We record a hash of .terraform.lock.hcl after init, and re-check before
#   plan/apply. If the hash doesn't match, we auto-run init again.
#   This prevents the common bug: "I forgot to init, why is Terraform confused?"
#
# Why `cd terraform` in every recipe:
#   The justfile lives at the repo root for convenience (so you can run from
#   anywhere in the repo). Terraform files are in terraform/. Every recipe
#   that runs terraform commands must cd into that directory first.
# ═════════════════════════════════════════════════════════════════════════════

# ─── Variables ───────────────────────────────────────────────────────────────

# Project name — appears in S3 key paths (e.g. "dev/kubecore")
project-name := "kubecore"

# Disable colored output in CI (logs are easier to read without ANSI codes)
no-color := if env("CI", "false") == "true" { "-no-color" } else { "" }

# Terraform working directory (relative to repo root, where this justfile lives)
tf-dir := "terraform"

# ─── Default recipe — shows help ─────────────────────────────────────────────

# Running `just` with no args lists available recipes
default:
    @just --list

# ═════════════════════════════════════════════════════════════════════════════
# Internal helpers (prefix with _, not meant to be called directly)
# ═════════════════════════════════════════════════════════════════════════════

# Initialize Terraform for a specific environment.
#
# Steps:
#   1. Wipe .terraform/ (cached config from a possibly-different env)
#   2. Wipe .tf_init_* marker files
#   3. Run terraform init with env-specific backend key + tfvars
#   4. Record a hash of the lock file so we know when re-init is needed
#
# Args:
# target = environment name (dev / staging / prod)
_init target:
    @echo "──────────────────────────────────────────────────────────"
    @echo "  Initializing Terraform for: {{ target }}"
    @echo "──────────────────────────────────────────────────────────"
    cd {{ tf-dir }} && rm -rf .terraform
    cd {{ tf-dir }} && rm -f .tf_init_*
    cd {{ tf-dir }} && terraform init \
        -input=false \
        -backend-config="key={{ target }}/{{ project-name }}" \
        -var-file={{ target }}.tfvars
    cd {{ tf-dir }} && sha224sum .terraform.lock.hcl > .tf_init_{{ target }}
    @echo ""
    @echo "✅ Initialized for env: {{ target }}"

# Run terraform plan for a specific environment.
#
# Auto-re-initializes if lock file changed since last init (handles forgotten
# init after provider updates or env switches).
_plan target:
    @# Re-init if the init marker is missing or lock file has changed
    cd {{ tf-dir }} && \
      (test -f ".tf_init_{{ target }}" && sha224sum --check --quiet ".tf_init_{{ target }}") \
      || just _init {{ target }}
    cd {{ tf-dir }} && terraform plan \
        -input=false \
        -out=tfplan \
        -lock-timeout=90s \
        -var-file={{ target }}.tfvars \
        {{ no-color }}

# Apply changes to a specific environment.
#
# Uses the saved plan from `_plan` if it exists, otherwise plans+applies fresh.
# `-lock-timeout=90s` waits up to 90 seconds for state lock (avoids spurious
# failures when state is briefly locked by a concurrent operation).
_apply target:
    cd {{ tf-dir }} && \
      (test -f ".tf_init_{{ target }}" && sha224sum --check --quiet ".tf_init_{{ target }}") \
      || just _init {{ target }}
    cd {{ tf-dir }} && terraform apply \
        -input=false \
        -lock-timeout=90s \
        -var-file={{ target }}.tfvars \
        {{ no-color }}

# Destroy all resources for an environment.
#
# Used at end of day for cost saving. Prompts for confirmation by default
# (Terraform's built-in safety).
_destroy target:
    cd {{ tf-dir }} && \
      (test -f ".tf_init_{{ target }}" && sha224sum --check --quiet ".tf_init_{{ target }}") \
      || just _init {{ target }}
    cd {{ tf-dir }} && terraform destroy \
        -input=false \
        -lock-timeout=90s \
        -var-file={{ target }}.tfvars \
        {{ no-color }}

# Run terraform fmt — formats all .tf files to canonical style.
# Should be run before committing. CI should run with -check to enforce.
_fmt:
    cd {{ tf-dir }} && terraform fmt -recursive

# Validate config syntax + types. Doesn't require AWS credentials.
# Useful in pre-commit / CI to catch typos early.
_validate target:
    cd {{ tf-dir }} && \
      (test -f ".tf_init_{{ target }}" && sha224sum --check --quiet ".tf_init_{{ target }}") \
      || just _init {{ target }}
    cd {{ tf-dir }} && terraform validate

# Show current state (lists all managed resources for the env).
_show target:
    cd {{ tf-dir }} && \
      (test -f ".tf_init_{{ target }}" && sha224sum --check --quiet ".tf_init_{{ target }}") \
      || just _init {{ target }}
    cd {{ tf-dir }} && terraform show

# ═════════════════════════════════════════════════════════════════════════════
# Public recipes — these are what you actually run day-to-day
# ═════════════════════════════════════════════════════════════════════════════

# ─── dev environment ─────────────────────────────────────────────────────────

# Initialize Terraform for dev (run once, or after env switch / provider update)
tf-init-dev: (_init "dev")

# Show what changes Terraform would make in dev
tf-plan-dev: (_plan "dev")

# Apply pending changes in dev
tf-apply-dev: (_apply "dev")

# Destroy all dev resources (cost-saving end of day)
tf-destroy-dev: (_destroy "dev")

# Validate dev config syntax (no AWS calls)
tf-validate-dev: (_validate "dev")

# Show current dev state
tf-show-dev: (_show "dev")

# ─── Add more envs here when needed ──────────────────────────────────────────
# init-staging: (_init "staging")
# plan-staging: (_plan "staging")
# apply-staging: (_apply "staging")
# destroy-staging: (_destroy "staging")
#
# init-prod: (_init "prod")
# plan-prod: (_plan "prod")
# apply-prod: (_apply "prod")
# destroy-prod: (_destroy "prod")

# ─── Cross-env utilities ─────────────────────────────────────────────────────

# Format all .tf files (run before commit)
tf-fmt: _fmt

# Show what env you're currently set up for (looks at marker files)
tf-current-env:
    @cd {{ tf-dir }} && ls .tf_init_* 2>/dev/null | sed 's/.tf_init_//' || echo "(none — run init-<env> first)"

# Print useful info about the kubecore setup
info:
    @echo "kubecore — platform infrastructure"
    @echo ""
    @echo "Terraform dir:  {{ tf-dir }}"
    @echo "Project name:   {{ project-name }}"
    @echo "Currently for:  $(cd {{ tf-dir }} && ls .tf_init_* 2>/dev/null | sed 's/.tf_init_//' || echo none)"
    @echo "AWS account:    $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "(not configured)")"
    @echo "AWS region:     $(aws configure get region 2>/dev/null || echo "(not configured)")"
    @echo ""
    @echo "Recipes: just --list"
