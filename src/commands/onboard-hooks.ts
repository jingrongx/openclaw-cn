import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { buildWorkspaceHookStatus } from "../hooks/hooks-status.js";
import { resolveAgentWorkspaceDir, resolveDefaultAgentId } from "../agents/agent-scope.js";
import { formatCliCommand } from "../cli/command-format.js";
import { t } from "../wizard/i18n.js";

export async function setupInternalHooks(
  cfg: OpenClawConfig,
  runtime: RuntimeEnv,
  prompter: WizardPrompter,
): Promise<OpenClawConfig> {
  await prompter.note(
    [
      "Hooks let you automate actions when agent commands are issued.",
      "Example: Save session context to memory when you issue /new.",
      "",
      "Learn more: https://docs.openclaw.ai/hooks",
    ].join("\n"),
    "Hooks",
  );

  // Discover available hooks using the hook discovery system
  const workspaceDir = resolveAgentWorkspaceDir(cfg, resolveDefaultAgentId(cfg));
  const report = buildWorkspaceHookStatus(workspaceDir, { config: cfg });

  // Show every eligible hook so users can opt in during onboarding.
  const eligibleHooks = report.hooks.filter((h) => h.eligible);

  if (eligibleHooks.length === 0) {
    await prompter.note(
      t("prompts.noHooks"),
      "No Hooks Available",
    );
    return cfg;
  }

  const toEnable = await prompter.multiselect({
    message: t("prompts.enableHooks"),
    options: [
      { value: "__skip__", label: t("prompts.skipForNow") },
      ...eligibleHooks.map((hook) => ({
        value: hook.name,
        label: `${hook.emoji ?? "🔗"} ${hook.name}`,
        hint: hook.description,
      })),
    ],
  });

  const selected = toEnable.filter((name) => name !== "__skip__");
  if (selected.length === 0) {
    return cfg;
  }

  // Enable selected hooks using the new entries config format
  const entries = { ...cfg.hooks?.internal?.entries };
  for (const name of selected) {
    entries[name] = { enabled: true };
  }

  const next: OpenClawConfig = {
    ...cfg,
    hooks: {
      ...cfg.hooks,
      internal: {
        enabled: true,
        entries,
      },
    },
  };

  await prompter.note(
    [
      t("prompts.hooksConfigured", {
        count: selected.length,
        names: selected.join(", "),
      }),
      "",
      "You can manage hooks later with:",
      `  ${formatCliCommand("openclaw hooks list")}`,
      `  ${formatCliCommand("openclaw hooks enable <name>")}`,
      `  ${formatCliCommand("openclaw hooks disable <name>")}`,
    ].join("\n"),
    "Hooks Configured",
  );

  return next;
}
