use anyhow::{Context, Result};
use serde::Deserialize;
use std::env;
use std::process::Command;

#[derive(Debug, Clone, Deserialize)]
pub struct AgentState {
    pub sync: String,
    #[serde(default)]
    pub github: String,
    #[serde(default)]
    pub eligibility: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeployInfo {
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AgentManifest {
    pub id: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub state: Option<AgentState>,
    #[serde(default)]
    pub deploy: Option<DeployInfo>,
    #[serde(default)]
    pub warnings: Vec<String>,
}

impl AgentManifest {
    pub fn sync_state(&self) -> &str {
        self.state.as_ref().map(|s| s.sync.as_str()).unwrap_or("unknown")
    }

    pub fn platform(&self) -> &str {
        self.deploy.as_ref().map(|d| d.platform.as_str()).unwrap_or("")
    }

    pub fn description(&self) -> &str {
        self.deploy.as_ref().map(|d| d.description.as_str()).unwrap_or("")
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct SkillManifest {
    pub id: String,
    #[serde(default)]
    pub state: Option<AgentState>,
    #[serde(default)]
    pub deploy: Option<DeployInfo>,
    #[serde(default)]
    pub warnings: Vec<String>,
}

impl SkillManifest {
    pub fn sync_state(&self) -> &str {
        self.state.as_ref().map(|s| s.sync.as_str()).unwrap_or("unknown")
    }

    pub fn platform(&self) -> &str {
        self.deploy.as_ref().map(|d| d.platform.as_str()).unwrap_or("")
    }

    pub fn description(&self) -> &str {
        self.deploy.as_ref().map(|d| d.description.as_str()).unwrap_or("")
    }
}

#[derive(Debug, Deserialize)]
struct AgentStatusResponse {
    agents: Vec<AgentManifest>,
}

#[derive(Debug, Deserialize)]
struct SkillStatusResponse {
    #[serde(default)]
    agents: Vec<SkillManifest>,
}

pub struct BackendConfig {
    pub python_helper: String,
    pub agents_db: String,
    pub skills_db: String,
    pub platform: String,
    pub runtime_dir: String,
    pub scope: String,
}

impl BackendConfig {
    pub fn from_env() -> Self {
        let agents_db = env::var("APM_TUI_AGENTS_DB")
            .or_else(|_| env::var("AGENTS_DB"))
            .unwrap_or_else(|_| {
                dirs_home().map(|h| format!("{}/agents_db", h)).unwrap_or_default()
            });
        let skills_db = env::var("APM_TUI_SKILLS_DB")
            .or_else(|_| env::var("SKILLS_DB"))
            .unwrap_or_else(|_| {
                dirs_home().map(|h| format!("{}/skills_db", h)).unwrap_or_default()
            });
        let platform = env::var("APM_TUI_PLATFORM")
            .or_else(|_| env::var("APM_PLATFORM"))
            .unwrap_or_else(|_| "claude-code".to_string());
        let runtime_dir = env::var("APM_TUI_RUNTIME_DIR").unwrap_or_default();
        let scope = env::var("APM_TUI_SCOPE").unwrap_or_else(|_| "global".to_string());

        // Find python helper relative to this binary or via env
        let python_helper = env::var("APM_PYTHON_HELPER").unwrap_or_else(|_| {
            // Try to find relative to APM_REPO or fallback
            env::var("APM_REPO")
                .map(|r| format!("{}/lib/py/apm_python.py", r))
                .unwrap_or_else(|_| "lib/py/apm_python.py".to_string())
        });

        Self { python_helper, agents_db, skills_db, platform, runtime_dir, scope }
    }
}

fn dirs_home() -> Option<String> {
    env::var("HOME").ok()
}

pub fn fetch_agents(cfg: &BackendConfig, platform: &str) -> Result<Vec<AgentManifest>> {
    let mut cmd = Command::new("python3");
    cmd.arg(&cfg.python_helper)
        .arg("status-agents")
        .arg("--db")
        .arg(&cfg.agents_db)
        .arg("--platform")
        .arg(platform);
    if !cfg.runtime_dir.is_empty() {
        cmd.arg("--runtime-dir").arg(&cfg.runtime_dir);
    }

    let out = cmd.output().context("failed to run apm_python.py")?;
    let json = String::from_utf8_lossy(&out.stdout);
    let resp: AgentStatusResponse =
        serde_json::from_str(&json).context("failed to parse agent status JSON")?;
    Ok(resp.agents)
}

pub fn fetch_skills(cfg: &BackendConfig, platform: &str) -> Result<Vec<SkillManifest>> {
    let mut cmd = Command::new("python3");
    cmd.arg(&cfg.python_helper)
        .arg("status-skills")
        .arg("--db")
        .arg(&cfg.skills_db)
        .arg("--platform")
        .arg(platform);
    if !cfg.runtime_dir.is_empty() {
        cmd.arg("--runtime-dir").arg(&cfg.runtime_dir);
    }

    let out = cmd.output().context("failed to run apm_python.py for skills")?;
    let json = String::from_utf8_lossy(&out.stdout);
    let resp: SkillStatusResponse =
        serde_json::from_str(&json).context("failed to parse skill status JSON")?;
    Ok(resp.agents)
}

pub fn run_apm_command(args: &[&str]) -> Result<String> {
    let apm_bin = env::var("APM_BIN").unwrap_or_else(|_| "apm".to_string());
    let out = Command::new(&apm_bin)
        .args(args)
        .output()
        .context("failed to run apm command")?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    if out.status.success() {
        Ok(stdout)
    } else {
        Ok(format!("{}\n{}", stdout, stderr))
    }
}
