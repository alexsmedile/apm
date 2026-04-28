use crate::backend::{AgentManifest, SkillManifest};

#[derive(Debug, Clone, PartialEq, Default)]
pub enum SortColumn {
    #[default]
    State,
    Name,
    Category,
    Platform,
}

impl SortColumn {
    pub fn next(&self) -> Self {
        match self {
            Self::State => Self::Name,
            Self::Name => Self::Category,
            Self::Category => Self::Platform,
            Self::Platform => Self::State,
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::State => "State",
            Self::Name => "Name",
            Self::Category => "Category",
            Self::Platform => "Platform",
        }
    }
}

pub fn filter_agents<'a>(
    agents: &'a [AgentManifest],
    query: &str,
    show_no_deploy: bool,
) -> Vec<&'a AgentManifest> {
    let q = query.to_lowercase();
    agents
        .iter()
        .filter(|a| {
            if !show_no_deploy && a.sync_state() == "no-deploy" {
                return false;
            }
            if q.is_empty() {
                return true;
            }
            a.id.to_lowercase().contains(&q)
                || a.category.to_lowercase().contains(&q)
                || a.description().to_lowercase().contains(&q)
        })
        .collect()
}

pub fn sort_agents(agents: &mut Vec<&AgentManifest>, col: &SortColumn) {
    agents.sort_by(|a, b| match col {
        SortColumn::State => state_order(a.sync_state()).cmp(&state_order(b.sync_state()))
            .then(a.id.cmp(&b.id)),
        SortColumn::Name => a.id.cmp(&b.id),
        SortColumn::Category => a.category.cmp(&b.category).then(a.id.cmp(&b.id)),
        SortColumn::Platform => a.platform().cmp(b.platform()).then(a.id.cmp(&b.id)),
    });
}

pub fn filter_skills<'a>(
    skills: &'a [SkillManifest],
    query: &str,
    show_no_deploy: bool,
) -> Vec<&'a SkillManifest> {
    let q = query.to_lowercase();
    skills
        .iter()
        .filter(|s| {
            if !show_no_deploy && s.sync_state() == "no-deploy" {
                return false;
            }
            if q.is_empty() {
                return true;
            }
            s.id.to_lowercase().contains(&q) || s.description().to_lowercase().contains(&q)
        })
        .collect()
}

pub fn sort_skills(skills: &mut Vec<&SkillManifest>, col: &SortColumn) {
    skills.sort_by(|a, b| match col {
        SortColumn::State => state_order(a.sync_state()).cmp(&state_order(b.sync_state()))
            .then(a.id.cmp(&b.id)),
        SortColumn::Name | SortColumn::Category => a.id.cmp(&b.id),
        SortColumn::Platform => a.platform().cmp(b.platform()).then(a.id.cmp(&b.id)),
    });
}

fn state_order(state: &str) -> u8 {
    match state {
        "invalid" | "orphan" | "collision" => 0,
        "outdated" => 1,
        "unmanaged" => 2,
        "ready" => 3,
        "installed" | "linked" => 4,
        "no-deploy" => 5,
        _ => 6,
    }
}
