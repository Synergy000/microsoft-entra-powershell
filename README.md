# Entra ID Group Management — CI/CD Pipeline

Automated group and membership management for Microsoft Entra ID using
**GitHub Actions** + **Microsoft Entra PowerShell**.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── manual-tasks.yml          # workflow_dispatch: create-groups | add-members
│       └── auto-tasks.yml            # Scheduled daily: birthright group1 + group2
│
├── scripts/
│   ├── common/
│   │   ├── Connect-EntraTenant.ps1   # Connect via service principal
│   │   └── Write-Log.ps1             # Timestamped INFO/WARN/ERROR logging
│   ├── manual-tasks/
│   │   ├── New-EntraGroups.ps1       # Create groups from data/input/groups.csv
│   │   └── Add-EntraGroupMembers.ps1 # Add members from data/input/members.csv
│   └── auto-tasks/
│       └── Add-BirthrightMembers.ps1 # Add users created in last 24 h to a group
│
├── data/
│   └── input/
│       ├── groups.csv                # Group definitions  (edit then commit)
│       └── members.csv               # Member assignments (edit then commit)
│
├── logs/
│   └── .gitkeep                      # Logs saved as GitHub Actions artifacts
│
└── README.md
```

---

## Branch → Environment Strategy

| Branch    | GitHub Environment | Tenant       | Triggered by          |
|-----------|--------------------|--------------|-----------------------|
| `test`    | `test`             | Test tenant  | `workflow_dispatch`   |
| `main`    | `production`       | Prod tenant  | `schedule` + `workflow_dispatch` |

Both workflows resolve the environment automatically from the branch at runtime.
**No duplicate workflow files.** No secret-name prefixes needed.

### Branching Workflow

```
feature/* ──PR──▶ test ──PR──▶ main
                   │              │
              test workflow   prod workflow
              (manual)        (manual + scheduled)
```

### Merge Prerequisites (enforced at runtime)

Each workflow includes a **`verify-merge`** gate job that runs _before_ any
Entra operations. If the prerequisite is not satisfied the run fails immediately
with an actionable error message — no credentials are consumed.

| Trigger branch | Gate check | Error if not met |
|----------------|------------|------------------|
| `test`  | `test` is ahead of `main` by ≥ 1 commit — i.e. a feature branch has been merged in | Merge a feature branch into `test` first |
| `main`  | `origin/test` is a full ancestor of `main` — i.e. `test` was merged into `main` | Open a PR `test → main` and complete it first |

> **Scheduled runs** (`auto-tasks.yml` cron) bypass the gate — they always
> execute on `main` and are not preceded by a manual merge step.

### Recommended Branch Protection Rules

| Branch | Setting |
|--------|---------|
| `test` | Require PR from `feature/*`; require 1 approving review |
| `main` | Require PR from `test` only; require 1 approving review; require status checks to pass |

---

## GitHub Environments & Secrets

Create two environments in **Settings → Environments**:

| Environment | Protection Rule | Secrets to configure |
|-------------|-----------------|----------------------|
| `test` | None | `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET`, `BIRTHRIGHT_GROUP1_ID`, `BIRTHRIGHT_GROUP2_ID` |
| `production` | **Required reviewers** | Same names — different values |

Using environment-scoped secrets with identical names keeps workflow files clean
(no `TEST_` / `PROD_` prefixes).

---

## Service Principal Permissions (both tenants)

| Permission | Type |
|------------|------|
| `Group.ReadWrite.All` | Application |
| `GroupMember.ReadWrite.All` | Application |

---

## Manual Tasks Workflow

**File:** [`.github/workflows/manual-tasks.yml`](.github/workflows/manual-tasks.yml)

Trigger: **Actions → Manual Tasks → Run workflow** (select branch + task)

| Input | Options |
|-------|---------|
| `task` | `create-groups` · `add-members` |

### create-groups

| Step | Action |
|------|--------|
| 1 | Edit [`data/input/groups.csv`](data/input/groups.csv) on a `feature/*` branch and commit |
| 2 | Open PR `feature/* → test` and merge |
| 3 | **Trigger workflow on `test` branch** → `verify-merge` gate passes → verify `create-groups_test_run{n}` artifact |
| 4 | Open PR `test → main` and merge |
| 5 | **Trigger workflow on `main` branch** → `verify-merge` gate passes → approve `production` environment gate → verify `create-groups_main_run{n}` artifact |

CSV format:
```csv
DisplayName,MailNickname,Description
SG-Finance-Readers,sg-finance-readers,Read access for Finance team
```

> Groups that already exist are **skipped** (idempotent — safe to re-run).

### add-members

| Step | Action |
|------|--------|
| 1 | Edit [`data/input/members.csv`](data/input/members.csv) on a `feature/*` branch and commit |
| 2 | Open PR `feature/* → test` and merge |
| 3 | **Trigger workflow on `test` branch** → `verify-merge` gate passes → verify `add-members_test_run{n}` artifact |
| 4 | Open PR `test → main` and merge |
| 5 | **Trigger workflow on `main` branch** → `verify-merge` gate passes → approve `production` environment gate → verify `add-members_main_run{n}` artifact |

CSV format:
```csv
GroupDisplayName,UserPrincipalName
SG-Finance-Readers,alice.smith@contoso.com
```

> Users already in the group are **skipped** (idempotent — safe to re-run).

---

## Auto Tasks Workflow

**File:** [`.github/workflows/auto-tasks.yml`](.github/workflows/auto-tasks.yml)

Trigger: **Daily at 00:00 AEDT** (`cron: '0 13 * * *'`) on `main` (Prod) — no merge gate.
`workflow_dispatch` on `test` or `main` for ad-hoc runs — **merge prerequisite enforced** (same rules as Manual Tasks above).

Runs a **matrix job** (group1 + group2 in parallel) — both groups are processed
in the same workflow run. `fail-fast: false` ensures group2 still runs if group1 fails.

| Matrix job | Secret used for GroupId |
|------------|-------------------------|
| `group1` | `BIRTHRIGHT_GROUP1_ID` |
| `group2` | `BIRTHRIGHT_GROUP2_ID` |

The script [`scripts/auto-tasks/Add-BirthrightMembers.ps1`](scripts/auto-tasks/Add-BirthrightMembers.ps1)
queries users created in the **last 24 hours** and adds them to the target group,
skipping any who are already members.

> **Timezone note:** `0 13 * * *` = 00:00 AEDT (UTC+11).
> During AEST (UTC+10) change to `0 14 * * *`.

---

## PowerShell Module Caching

Both workflows cache the `Microsoft.Entra` module between runs using `actions/cache`.
The cache is keyed on `PS_MODULE_CACHE_KEY` (default `v1`).

To force a fresh module install (e.g. after a version upgrade), bump the value
in the workflow `env` block:

```yaml
env:
  PS_MODULE_CACHE_KEY: v2   # was v1
```

---

## Log Artifacts

All runs upload logs to **GitHub Actions Artifacts** (90-day retention).

| Artifact name | Workflow | Branch |
|---------------|----------|--------|
| `create-groups_{branch}_run{n}` | Manual Tasks | any |
| `add-members_{branch}_run{n}` | Manual Tasks | any |
| `birthright-group1_{branch}_run{n}` | Auto Tasks | any |
| `birthright-group2_{branch}_run{n}` | Auto Tasks | any |

Download: **Actions → (select run) → Artifacts**

Log format:
```
[2024-01-15 13:00:01] [INFO ] [Test] Connected. Processing 'data/input/groups.csv' (3 row(s))...
[2024-01-15 13:00:02] [INFO ] CREATED | SG-Finance-Readers
[2024-01-15 13:00:02] [INFO ] SKIP    | SG-HR-Contributors — group already exists
[2024-01-15 13:00:03] [ERROR] FAILED  | SG-IT-Admins | ...
[2024-01-15 13:00:03] [INFO ] Summary | Created: 1 | Skipped: 1 | Failed: 1
```
