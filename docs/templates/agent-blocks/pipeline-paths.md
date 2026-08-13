## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/<slug>-design.md` |
| Board tasks | `docs/superpowers/tasks/<slug>/NN-*.md` |
| Issue map | `docs/superpowers/tasks/<slug>/.issue-map.json` |
| Designs | `docs/supersaiyan/designs/<slug>-design.md` |

When saving design docs from external tools, also save a copy to
`docs/supersaiyan/designs/<name>-design.md`.

Files under `.claude/skills/` are installed copies — do not hand-edit them. Change them in the
SuperSaiyan checkout and re-run `install.sh`.

SuperSaiyan passes sandbox and approval flags per invocation when it dispatches headless
workers. Do not pin `sandbox_mode` or `approval_policy` in a Codex `config.toml` for this
repo — that would put the same setting in two places, and it would widen permissions for every
interactive session too, not just SuperSaiyan's workers.
