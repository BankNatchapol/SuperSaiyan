# Agent notes


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

## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/<slug>-design.md` |
| Board tasks | `docs/superpowers/tasks/<slug>/NN-*.md` |
| Issue map | `docs/superpowers/tasks/<slug>/.issue-map.json` |
| Designs | `docs/gstack/designs/<slug>-design.md` |

When saving design docs from `/office-hours` or similar tools, also save a
copy to `docs/gstack/designs/<feature-slug>-design.md`.
