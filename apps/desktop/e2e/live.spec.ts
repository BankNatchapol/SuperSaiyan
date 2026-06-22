import { expect, test } from "@playwright/test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createTestWorkspace, launchControlCenter, seedRegistry } from "./helpers";

const exec = promisify(execFile);
const enabled = process.env.SUPERSAIYAN_LIVE_E2E === "1";

async function gh(cwd: string, args: string[]): Promise<string> {
  const result = await exec("gh", args, { cwd, encoding: "utf8", maxBuffer: 8 * 1024 * 1024 });
  return result.stdout.trim();
}

test("@live creates and cleans a private GitHub repository and Project", async () => {
  test.skip(!enabled, "Set SUPERSAIYAN_LIVE_E2E=1 to allow disposable GitHub mutations");
  const owner = await gh(process.cwd(), ["api", "user", "--jq", ".login"]);
  const authHeaders = await gh(process.cwd(), ["api", "-i", "user"]);
  if (!/^x-oauth-scopes:.*\bdelete_repo\b/im.test(authHeaders)) {
    throw new Error("Live E2E requires the delete_repo scope before creating resources. Run: gh auth refresh -h github.com -s delete_repo");
  }
  const suffix = `${Date.now()}-${process.pid}`;
  const repoName = `supersaiyan-e2e-${suffix}`;
  const projectTitle = `SuperSaiyan E2E ${suffix}`;
  const checkout = await mkdtemp(join(tmpdir(), "supersaiyan-live-"));
  const cleanup: string[] = [];
  let projectNumber: number | undefined;

  try {
    await gh(checkout, ["repo", "create", `${owner}/${repoName}`, "--private", "--add-readme", "--clone"]);
    cleanup.push(`gh repo delete ${owner}/${repoName} --yes`);
    const repoPath = join(checkout, repoName);
    const project = JSON.parse(await gh(repoPath, ["project", "create", "--owner", owner, "--title", projectTitle, "--format", "json"]));
    projectNumber = Number(project.number);
    cleanup.unshift(`gh project delete ${projectNumber} --owner ${owner}`);
    await writeFile(join(checkout, "cleanup-manifest.txt"), `${cleanup.join("\n")}\n`);

    const fieldList = JSON.parse(await gh(repoPath, ["project", "field-list", String(projectNumber), "--owner", owner, "--format", "json"]));
    const statusField = fieldList.fields.find((field: any) => field.name === "Status");
    if (!statusField) throw new Error("Disposable Project did not create a Status field");
    const mutation = `mutation($field:ID!,$options:[ProjectV2SingleSelectFieldOptionInput!]!){
      updateProjectV2Field(input:{fieldId:$field,singleSelectOptions:$options}){
        projectV2Field{... on ProjectV2SingleSelectField{id}}
      }
    }`;
    const statuses = ["Backlog", "Ready", "Building", "QA", "Review", "Done", "Blocked", "Skipped"];
    const graphqlInput = join(checkout, "update-status-field.json");
    await writeFile(graphqlInput, JSON.stringify({
      query: mutation,
      variables: {
        field: statusField.id,
        options: statuses.map((name, index) => ({
        name,
        color: ["GRAY", "YELLOW", "BLUE", "CYAN", "PURPLE", "GREEN", "RED", "GRAY"][index],
        description: `E2E ${name}`,
        })),
      },
    }));
    await gh(repoPath, ["api", "graphql", "--input", graphqlInput]);
    const refreshedFields = JSON.parse(await gh(repoPath, ["project", "field-list", String(projectNumber), "--owner", owner, "--format", "json"]));
    const options = refreshedFields.fields.find((field: any) => field.name === "Status").options;
    const projectId = JSON.parse(await gh(repoPath, ["project", "view", String(projectNumber), "--owner", owner, "--format", "json"])).id;

    for (let index = 0; index < statuses.length; index += 1) {
      const status = statuses[index];
      const issueUrl = await gh(repoPath, [
        "issue", "create",
        "--repo", `${owner}/${repoName}`,
        "--title", `E2E ${status}`,
        "--body", index === 1 ? "Depends on: #1" : `Disposable ${status} card`,
      ]);
      const issueNumber = Number(issueUrl.split("/").at(-1));
      if (status === "Building") await gh(repoPath, ["issue", "edit", String(issueNumber), "--repo", `${owner}/${repoName}`, "--add-assignee", owner]);
      const item = JSON.parse(await gh(repoPath, ["project", "item-add", String(projectNumber), "--owner", owner, "--url", issueUrl, "--format", "json"]));
      const option = options.find((candidate: any) => candidate.name === status);
      await gh(repoPath, [
        "project", "item-edit",
        "--id", item.id,
        "--project-id", projectId,
        "--field-id", statusField.id,
        "--single-select-option-id", option.id,
      ]);
      if (status === "Done") await gh(repoPath, ["issue", "close", String(issueNumber), "--repo", `${owner}/${repoName}`]);
    }

    const configDir = join(repoPath, ".claude", "supersaiyan", "configs");
    await mkdir(configDir, { recursive: true });
    await writeFile(join(repoPath, ".claude", "supersaiyan", "active"), "live\n");
    await writeFile(join(configDir, "live.json"), JSON.stringify({
      variant: "full",
      base_branch: "main",
      project: { owner, number: projectNumber, title: projectTitle },
    }, null, 2));
    await mkdir(join(repoPath, ".claude", "skills", "supersaiyan"), { recursive: true });
    await writeFile(join(repoPath, ".claude", "skills", "supersaiyan", "SKILL.md"), "---\nname: supersaiyan\n---\n");

    const workspace = await createTestWorkspace();
    workspace.repoA = repoPath;
    await seedRegistry(workspace, [repoPath]);
    const { app, page } = await launchControlCenter(workspace, { PATH: process.env.PATH || "" });
    try {
      await page.getByRole("button", { name: /^Board/ }).click();
      for (const status of statuses) await expect(page.locator(".lane-header", { hasText: status })).toBeVisible();
      const backlog = page.locator(".issue-card", { hasText: "E2E Backlog" });
      const readyLane = page.locator(".lane", { has: page.locator(".lane-header", { hasText: "Ready" }) });
      await backlog.dragTo(readyLane);
      await expect(readyLane.locator(".issue-card", { hasText: "E2E Backlog" })).toBeVisible();
    } finally {
      await app.close();
      await workspace.cleanup();
    }
  } finally {
    const failures: string[] = [];
    if (projectNumber) {
      try { await gh(checkout, ["project", "delete", String(projectNumber), "--owner", owner]); }
      catch (error) { failures.push(`gh project delete ${projectNumber} --owner ${owner}`); }
    }
    try { await gh(checkout, ["repo", "delete", `${owner}/${repoName}`, "--yes"]); }
    catch (error) { failures.push(`gh repo delete ${owner}/${repoName} --yes`); }
    await rm(checkout, { recursive: true, force: true });
    expect(failures, `Cleanup failed. Run:\n${failures.join("\n")}`).toEqual([]);
  }
});
