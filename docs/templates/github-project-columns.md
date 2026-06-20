# GitHub Project setup — column checklist

Use this when creating your Project board (Step 10). **Spelling must match exactly** — super-board looks for these `Status` values.

## Create the project

Pick **one** path below. **Path A** is simplest — the project is linked to your repo automatically.

### Path A — Create from your app repo (recommended)

1. Open your app repo on GitHub: `https://github.com/YOUR_GH_USER/my-first-agent-app`
2. Click the **Projects** tab (next to Pull requests).
3. Click **New project**.
4. Choose **Board** (GitHub Projects v2 — not “classic” projects).
5. Name it e.g. `my-first-agent-app`.
6. Click **Create project**.

The board opens already tied to this repository.

### Path B — You already created a standalone project

Link it to the repo:

1. Open your app repo → **Projects** tab.
2. Click **Link a project**.
3. Search for your project name (same owner as the repo — your user or your org).
4. Click the project to attach it.

Official guide: [Adding your project to a repository](https://docs.github.com/en/issues/planning-and-tracking-with-projects/managing-your-project/adding-your-project-to-a-repository)

**Optional — default repo from the project side:** Open the project → **⋯** (top right) → **Settings** → under **Default repository**, choose your app repo → **Save**. New issues added from the board then default to that repo.

### Path C — Terminal (`gh`)

From your app repo folder:

```bash
cd ~/Documents/my-first-agent-app
gh project create --owner @me --title my-first-agent-app --format json
```

Note the `"number"` in the output. Then link (if not already linked):

```bash
gh project link <number> --owner @me --repo YOUR_GH_USER/my-first-agent-app
```

List projects to find `number` later:

```bash
gh project list --owner @me
```

Official guide: [Planning and tracking with Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects)

## Link the project to your repo — verify

You only need **one** of these checks to pass:

- [ ] Repo **Projects** tab lists your board, **or**
- [ ] Project **Settings** → **Default repository** = your app repo

If neither is true, use Path B or C above before `/super-board onboard`.

## Owner and project number (for `/super-board onboard`)

super-board needs:

| Field | Meaning | Example |
|-------|---------|---------|
| **owner** | GitHub user or org that owns the project | `YOUR_GH_USER` or `my-org` |
| **number** | Numeric ID in the project URL (not the project title) | `3` |

**From the browser:** open the project. The URL looks like one of:

```text
https://github.com/users/YOUR_GH_USER/projects/3
https://github.com/orgs/MY_ORG/projects/3
```

- **owner** = `YOUR_GH_USER` or `MY_ORG`
- **number** = `3`

**From Terminal:**

```bash
gh project list --owner @me
```

Use the **NUMBER** column. For an org-owned project, add `--owner MY_ORG`.

**During onboard:** when asked, give that **owner** and **number**. The wizard may also list your projects — pick the one you just created.

---

## Status field and columns

Your project needs a single-select field named **`Status`** (default in many templates) with **exactly** these options:

| Column name | Used for |
|-------------|----------|
| `Backlog` | Planned work; agents ignore |
| `Ready` | Scoped work; agents pick up from here |
| `Building` | Builder lane in progress |
| `QA` | Tester lane in progress |
| `Review` | Reviewer lane in progress |
| `Done` | Merged / complete |
| `Blocked` | Needs human (conflict, creds, etc.) |
| `Skipped` | Won't do |

If your template uses different names, rename columns to match the table above.

## Add an issue to the board

1. Create an issue (see [issue.md](issue.md)).
2. In the project board, click **+ Add item** → select your issue.
3. Leave it in **Backlog** while reviewing acceptance criteria (Step 13), then
   onboard super-board (Step 14) before moving eligible cards to Ready (Step 15)
   in [GETTING-STARTED.md](../GETTING-STARTED.md).

## Verify

- [ ] Project is GitHub Projects **v2** (not the old classic projects)
- [ ] `Status` field exists with all 8 column names spelled as above
- [ ] You know `owner` (your user or org) and project `number`
