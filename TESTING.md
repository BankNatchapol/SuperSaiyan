# Testing SuperSaiyan

The Control Center uses Vitest for unit tests and Playwright's Electron API for
end-to-end testing. Test repositories, Electron user data, command logs, and
GitHub responses are created under temporary directories and never use an
existing app repository such as Ptest.

## Commands

```bash
npm test                       # unit and shell-adjacent tests
npm run lint                   # TypeScript checks
npm run test:e2e               # deterministic Electron/IPC/PTY suite
npm run test:e2e:packaged      # packaged native-resource and PTY smoke
npm run test:control-center    # normal local acceptance suite
```

Playwright artifacts are written to `apps/desktop/test-results/`, including
HTML output, JSON results, screenshots, traces, and failure video.

## Live GitHub sandbox

The live test creates a uniquely named private repository and Project under the
active GitHub account. It never targets an existing repository or Project.

Before the first run, grant the GitHub CLI permission to delete disposable
repositories:

```bash
gh auth refresh -h github.com -s delete_repo
```

Then run:

```bash
SUPERSAIYAN_LIVE_E2E=1 npm run test:e2e:live
```

The test verifies the `delete_repo` scope before creating anything, records
cleanup commands immediately, and deletes the Project and repository in a
`finally` block. If cleanup fails, the test fails and prints exact commands.

## Report-only exploratory QA

The baseline report belongs under:

```text
.gstack/qa-reports/control-center/
```

Run deterministic tests first, then use `$qa` in exhaustive report-only mode.
Do not fix application source during the baseline pass. Each issue requires a
reproduction, severity, category, and screenshot or trace reference.
