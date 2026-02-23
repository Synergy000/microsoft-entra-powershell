# Entra ID Group Management — CI/CD Pipeline

Automated group and membership management for Microsoft Entra ID using
**GitHub Actions** + **Microsoft Entra PowerShell**.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── manual-tasks.yml          # Create groups / add members → Dev tenant
│       ├── manual-tasks-test.yml     # Create groups / add members → Test tenant
│       ├── auto-tasks.yml            # Daily 12 AM: add new joiners to Group 1 → Dev tenant
│       └── auto-tasks-test.yml       # Daily  1 AM: add new joiners to Group 2 → Test tenant
│
├── config/
│   └── pipeline.psd1                 # Shared settings (CSV paths)
│
├── scripts/
│   ├── common/
│   │   ├── Connect-EntraTenant.ps1   # Connect via service principal
│   │   └── Write-Log.ps1             # Timestamped INFO/WARN/ERROR logging
│   ├── manual-tasks/
│   │   ├── New-EntraGroups.ps1       # Create groups from groups.csv
│   │   └── Add-EntraGroupMembers.ps1 # Add members from members.csv
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

## Branch Strategy

```
feature/* ──PR──▶ dev ──PR──▶ test
                   │             │
            Dev workflows    Test workflows
```

| Branch    | GitHub Environment | Tenant      |
|-----------|--------------------|-------------|
| `feature/*` | —                | —           |
| `dev`     | `dev`              | Dev tenant  |
| `test`    | `test`             | Test tenant |

---

## GitHub Environments & Secrets

Go to **Settings → Environments** and create two environments:

| Environment | Secrets to add |
|-------------|----------------|
| `dev`  | `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET`, `BIRTHRIGHT_GROUP1_ID` |
| `test` | `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET`, `BIRTHRIGHT_GROUP2_ID` |

> Each environment holds the credentials for its own tenant.
> `BIRTHRIGHT_GROUP1_ID` and `BIRTHRIGHT_GROUP2_ID` are the Object IDs of the target groups.

---

## Service Principal Permissions (both tenants)

| Permission | Type |
|------------|------|
| `Group.ReadWrite.All` | Application |
| `GroupMember.ReadWrite.All` | Application |

---

## Manual Workflows

### Workflow 1 — Create groups / Add members in **Dev**

**File:** [`.github/workflows/manual-tasks.yml`](.github/workflows/manual-tasks.yml)

| Trigger | What happens |
|---------|--------------|
| PR merged `feature/* → dev` | Both tasks run automatically |
| `workflow_dispatch` (select branch `dev`) | You choose one task |

**Steps to deploy to Dev:**
1. Create a `feature/*` branch, edit [`data/input/groups.csv`](data/input/groups.csv) and/or [`data/input/members.csv`](data/input/members.csv), then commit and push.
2. Open a Pull Request from `feature/*` → `dev` and merge it.
3. The **Manual Tasks — Dev** workflow triggers automatically and runs both tasks.
4. Check the `manual-tasks_dev_run{n}` artifact in Actions for the log.

---

### Workflow 2 — Create groups / Add members in **Test**

**File:** [`.github/workflows/manual-tasks-test.yml`](.github/workflows/manual-tasks-test.yml)

| Trigger | What happens |
|---------|--------------|
| PR merged `dev → test` | Both tasks run automatically |
| `workflow_dispatch` (select branch `test`) | You choose one task |

**Steps to deploy to Test:**
1. After the Dev run is verified, open a Pull Request from `dev` → `test` and merge it.
2. The **Manual Tasks — Test** workflow triggers automatically and runs both tasks.
3. Check the `manual-tasks_test_run{n}` artifact in Actions for the log.

---

### CSV Formats

**groups.csv** — used by `create-groups`:
```csv
DisplayName,MailNickname,Description
SG-Finance-Readers,sg-finance-readers,Read access for Finance team
```

**members.csv** — used by `add-members`:
```csv
GroupDisplayName,UserPrincipalName
SG-Finance-Readers,alice.smith@contoso.com
```

> Both scripts are **idempotent** — groups/members that already exist are skipped. Safe to re-run.

---

## Auto Workflows

### Workflow 3 — Daily birthright: add new joiners to **Group 1** (Dev)

**File:** [`.github/workflows/auto-tasks.yml`](.github/workflows/auto-tasks.yml)

| Trigger | Schedule |
|---------|----------|
| Automatic | Every day at **12:00 AM AEDT** (UTC+11) |
| Manual | `workflow_dispatch` on any branch |

Finds all users created in the **last 24 hours** in the Dev tenant and adds them to Group 1.
Uses the `BIRTHRIGHT_GROUP1_ID` secret from the `dev` environment.

---

### Workflow 4 — Daily birthright: add new joiners to **Group 2** (Test)

**File:** [`.github/workflows/auto-tasks-test.yml`](.github/workflows/auto-tasks-test.yml)

| Trigger | Schedule |
|---------|----------|
| Automatic | Every day at **1:00 AM AEDT** (UTC+11) |
| Manual | `workflow_dispatch` on any branch |

Finds all users created in the **last 24 hours** in the Test tenant and adds them to Group 2.
Uses the `BIRTHRIGHT_GROUP2_ID` secret from the `test` environment.

---

## Log Artifacts

All runs save logs as **GitHub Actions Artifacts** (retained 90 days).
Go to **Actions → select a run → Artifacts** to download.

| Artifact name | Workflow |
|---------------|----------|
| `manual-tasks_dev_run{n}` | Manual Tasks — Dev |
| `manual-tasks_test_run{n}` | Manual Tasks — Test |
| `birthright-group1_dev_run{n}` | Auto Tasks — Dev |
| `birthright-group2_test_run{n}` | Auto Tasks — Test |

**Log format:**
```
[2024-01-15 13:00:01] [INFO ] [Dev] Processing 'data/input/groups.csv' (3 rows)...
[2024-01-15 13:00:02] [INFO ] CREATED | SG-Finance-Readers
[2024-01-15 13:00:02] [INFO ] SKIP    | SG-HR-Contributors — already exists
[2024-01-15 13:00:03] [ERROR] FAILED  | SG-IT-Admins | <error message>
[2024-01-15 13:00:03] [INFO ] Done — Created: 1 | Skipped: 1 | Failed: 1
```

---

## Timezone Reference

GitHub Actions schedules run in UTC. AEDT is UTC+11.

| Local time (AEDT) | Cron (UTC) | Used by |
|-------------------|------------|---------|
| 12:00 AM AEDT | `0 13 * * *` | Auto Tasks — Dev (Group 1) |
|  1:00 AM AEDT | `0 14 * * *` | Auto Tasks — Test (Group 2) |

> During AEST (UTC+10, Apr–Oct), update to `0 14 * * *` and `0 15 * * *` respectively.
