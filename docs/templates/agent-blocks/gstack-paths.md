## gstack artifact paths (SuperSaiyan)

When you run **gstack** `/office-hours` or `/spec` in this repo, **also save a copy** in the repo:

| Skill | Primary gstack path (default) | **Repo copy (required)** |
|-------|------------------------------|---------------------------|
| `/office-hours` | `~/.gstack/projects/<slug>/*-design-*.md` | `docs/gstack/designs/<feature-slug>-design.md` |
| `/spec` | `~/.gstack/projects/<slug>/specs/*.md` | `docs/gstack/specs/<feature-slug>-spec.md` |

**Super-board / superpowers pipeline** uses the refined spec at:

`docs/superpowers/specs/<feature-slug>-design.md`

After `/office-hours`, run **refining-spec** (or copy) so that file exists before **writing-board-tasks**.

Do not skip the repo copy — agents and git only see files under this repository.
