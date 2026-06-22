import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const harnessRoot = path.dirname(scriptPath);
const repoRoot = path.resolve(harnessRoot, "..", "..");
const configPath = path.join(harnessRoot, "harness.config.json");
const config = JSON.parse(readFileSync(configPath, "utf8"));

const failures = [];
const warnings = [];

function relPath(filePath) {
  return path.relative(repoRoot, filePath) || ".";
}

function record(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function warn(condition, message) {
  if (!condition) {
    warnings.push(message);
  }
}

function fileExists(relativePath) {
  return existsSync(path.join(repoRoot, relativePath));
}

function readSource(relativePath) {
  const absolutePath = path.join(repoRoot, relativePath);
  record(existsSync(absolutePath), `Missing source: ${relativePath}`);
  return existsSync(absolutePath) ? readFileSync(absolutePath, "utf8") : "";
}

function git(root, args) {
  try {
    return execFileSync("git", args, {
      cwd: root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    }).trim();
  } catch (error) {
    failures.push(`Git command failed in ${root}: git ${args.join(" ")}`);
    return "";
  }
}

const projectGoals = readSource(config.sources.projectGoals);
const todayQueue = readSource(config.sources.todayQueue);
const projectMemory = readSource(config.sources.projectMemory);

record(config.mode === "read-only", "Harness mode must be read-only");
record(config.allowWrites === false, "Harness writes must be disabled");
record(config.allowDeploys === false, "Harness deploys must be disabled");
record(config.allowInstalls === false, "Harness installs must be disabled");
record(config.allowCommits === false, "Harness commits must be disabled");

for (const [sourceName, sourcePath] of Object.entries(config.sources)) {
  if (sourceName.endsWith("Root")) {
    record(existsSync(path.join(repoRoot, sourcePath)), `Missing source directory: ${sourcePath}`);
  } else {
    record(fileExists(sourcePath), `Missing source file: ${sourcePath}`);
  }
}

for (const [projectName, activeTask] of Object.entries(config.activeTasks)) {
  record(fileExists(activeTask.task), `Missing task for ${projectName}: ${activeTask.task}`);
  record(fileExists(activeTask.report), `Missing report for ${projectName}: ${activeTask.report}`);
  record(projectGoals.includes(activeTask.task), `PROJECT_GOALS does not reference ${activeTask.task}`);
  record(todayQueue.includes(activeTask.task), `TODAY_QUEUE does not reference ${activeTask.task}`);
  warn(projectMemory.toLowerCase().includes(projectName), `PROJECT_MEMORY may not mention ${projectName}`);

  const taskBody = readSource(activeTask.task);
  for (const required of ["goal", "current status", "acceptance criteria", "verification method", "blockers", "priority"]) {
    record(taskBody.toLowerCase().includes(required), `${activeTask.task} missing required section text: ${required}`);
  }
}

const projectResults = {};

for (const [projectName, project] of Object.entries(config.projects)) {
  const rootExists = existsSync(project.root);
  record(rootExists, `Missing project root for ${projectName}: ${project.root}`);

  if (!rootExists) {
    continue;
  }

  const branch = git(project.root, ["branch", "--show-current"]);
  const remotes = git(project.root, ["remote", "-v"]);
  const status = git(project.root, ["status", "--short"]);

  record(branch === project.expectedBranch, `${projectName} branch mismatch: expected ${project.expectedBranch}, got ${branch || "<empty>"}`);
  record(remotes.includes(project.expectedRemote), `${projectName} remote mismatch: expected ${project.expectedRemote}`);

  projectResults[projectName] = {
    root: project.root,
    branch,
    remote: project.expectedRemote,
    worktree: status ? "dirty" : "clean"
  };
}

console.log(`Harness ${config.version}`);
console.log(`Mode: ${config.mode}`);
console.log(`Repository location: ${relPath(harnessRoot)}`);
console.log(`Startup command: node tools/harness-poc/check-queue.mjs`);
console.log("");
console.log("Integration status:");
console.log(`- PROJECT_MEMORY: ${fileExists(config.sources.projectMemory) ? "present" : "missing"}`);
console.log(`- PROJECT_GOALS: ${fileExists(config.sources.projectGoals) ? "present" : "missing"}`);
console.log(`- TODAY_QUEUE: ${fileExists(config.sources.todayQueue) ? "present" : "missing"}`);
console.log(`- TASKS: ${existsSync(path.join(repoRoot, config.sources.tasksRoot)) ? "present" : "missing"}`);
console.log(`- REPORTS: ${existsSync(path.join(repoRoot, config.sources.reportsRoot)) ? "present" : "missing"}`);
console.log("");
console.log("Project roots:");
for (const [projectName, result] of Object.entries(projectResults)) {
  console.log(`- ${projectName}: ${result.root} | ${result.branch} | ${result.worktree}`);
}
console.log("");

if (warnings.length > 0) {
  console.log("Warnings:");
  for (const warning of warnings) {
    console.log(`- ${warning}`);
  }
  console.log("");
}

if (failures.length > 0) {
  console.log("Failures:");
  for (const failure of failures) {
    console.log(`- ${failure}`);
  }
  process.exitCode = 1;
} else {
  console.log("Result: PASS");
}

