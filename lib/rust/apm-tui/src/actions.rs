use crate::backend::{AgentManifest, SkillManifest};

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Install,
    Update,
    Diff,
    Link,
    Unlink,
    GithubPush,
    GithubPull,
    Validate,
    Import,
    Remove,
    Cancel,
}

impl Action {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Install => "Install",
            Self::Update => "Update",
            Self::Diff => "Diff",
            Self::Link => "Link",
            Self::Unlink => "Unlink",
            Self::GithubPush => "GitHub Push",
            Self::GithubPull => "GitHub Pull",
            Self::Validate => "Validate",
            Self::Import => "Import",
            Self::Remove => "Remove (runtime)",
            Self::Cancel => "Cancel",
        }
    }

    pub fn to_apm_args(&self, id: &str, platform: &str) -> Vec<String> {
        match self {
            Self::Install => vec!["--platform".into(), platform.into(), "install".into(), id.into()],
            Self::Update => vec!["--platform".into(), platform.into(), "update".into(), id.into()],
            Self::Diff => vec!["--platform".into(), platform.into(), "diff".into(), id.into()],
            Self::Link => vec!["--platform".into(), platform.into(), "link".into(), id.into()],
            Self::Unlink => vec!["--platform".into(), platform.into(), "unlink".into(), id.into()],
            Self::GithubPush => vec!["github".into(), "push".into(), id.into()],
            Self::GithubPull => vec!["github".into(), "pull".into(), id.into()],
            Self::Validate => vec!["validate".into(), id.into()],
            Self::Import => vec!["import".into(), id.into()],
            Self::Remove => vec!["--platform".into(), platform.into(), "remove".into(), id.into()],
            Self::Cancel => vec![],
        }
    }
}

pub fn agent_actions(state: &str) -> Vec<Action> {
    match state {
        "ready" => vec![Action::Install, Action::Validate, Action::Cancel],
        "installed" | "linked" => vec![
            Action::Update,
            Action::Diff,
            Action::Unlink,
            Action::GithubPush,
            Action::GithubPull,
            Action::Validate,
            Action::Cancel,
        ],
        "outdated" => vec![
            Action::Update,
            Action::Install,
            Action::Diff,
            Action::Validate,
            Action::Cancel,
        ],
        "unmanaged" => vec![Action::Import, Action::Validate, Action::Cancel],
        "orphan" => vec![Action::Remove, Action::Validate, Action::Cancel],
        "invalid" => vec![Action::Validate, Action::Cancel],
        "no-deploy" => vec![Action::Cancel],
        _ => vec![Action::Validate, Action::Cancel],
    }
}

pub fn skill_actions(state: &str) -> Vec<Action> {
    match state {
        "ready" => vec![Action::Install, Action::Cancel],
        "linked" | "installed" => vec![Action::Unlink, Action::GithubPush, Action::Cancel],
        "outdated" => vec![Action::Install, Action::Unlink, Action::Cancel],
        "unmanaged" => vec![Action::Import, Action::Cancel],
        "orphan" => vec![Action::Remove, Action::Cancel],
        _ => vec![Action::Cancel],
    }
}

pub struct AgentPopup {
    pub id: String,
    pub state: String,
    pub platform: String,
    pub actions: Vec<Action>,
    pub selected: usize,
}

impl AgentPopup {
    pub fn for_agent(agent: &AgentManifest, platform: &str) -> Self {
        let state = agent.sync_state().to_string();
        let actions = agent_actions(&state);
        Self {
            id: agent.id.clone(),
            state,
            platform: platform.to_string(),
            actions,
            selected: 0,
        }
    }

    pub fn for_skill(skill: &SkillManifest, platform: &str) -> Self {
        let state = skill.sync_state().to_string();
        let actions = skill_actions(&state);
        Self {
            id: skill.id.clone(),
            state,
            platform: platform.to_string(),
            actions,
            selected: 0,
        }
    }

    pub fn move_up(&mut self) {
        if self.selected > 0 {
            self.selected -= 1;
        }
    }

    pub fn move_down(&mut self) {
        if self.selected + 1 < self.actions.len() {
            self.selected += 1;
        }
    }

    pub fn current_action(&self) -> &Action {
        &self.actions[self.selected]
    }
}
