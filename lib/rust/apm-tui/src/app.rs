use crate::actions::AgentPopup;
use crate::backend::{AgentManifest, BackendConfig, SkillManifest};
use crate::config_writer::{load_config_fields, ConfigField};
use crate::filter::SortColumn;

pub const AGENT_PLATFORMS: &[&str] = &[
    "claude-code", "cursor", "codex", "gemini", "windsurf", "continue", "agents-dir", "generic",
];
pub const SKILL_PLATFORMS: &[&str] = &["claude-code", "codex", "windsurf", "agents-dir"];

#[derive(Debug, Clone, PartialEq)]
pub enum Tab {
    Agents,
    Skills,
    Config,
}

impl Tab {
    pub fn next(&self) -> Self {
        match self {
            Self::Agents => Self::Skills,
            Self::Skills => Self::Config,
            Self::Config => Self::Agents,
        }
    }

    pub fn prev(&self) -> Self {
        match self {
            Self::Agents => Self::Config,
            Self::Skills => Self::Agents,
            Self::Config => Self::Skills,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum InputMode {
    Normal,
    Filter,
    PlatformSelect,
    ActionPopup,
    OutputPane,
    ConfigEdit,
}

pub struct App {
    pub config: BackendConfig,
    pub tab: Tab,
    pub input_mode: InputMode,

    // data
    pub agents: Vec<AgentManifest>,
    pub skills: Vec<SkillManifest>,
    pub config_fields: Vec<ConfigField>,

    // navigation
    pub list_index: usize,

    // platform selection
    pub active_agent_platform: String,
    pub active_skill_platform: String,
    pub platform_cursor: usize,

    // filter
    pub filter_query: String,
    pub show_no_deploy: bool,
    pub sort_col: SortColumn,

    // popup
    pub popup: Option<AgentPopup>,

    // output pane
    pub output: String,
    pub output_scroll: usize,

    // config editing
    pub config_edit_index: usize,
    pub config_edit_value: String,
    pub config_dirty: bool,

    // status
    pub status_msg: Option<String>,
    pub loading: bool,
    pub error: Option<String>,
    pub should_quit: bool,
}

impl App {
    pub fn new(config: BackendConfig) -> Self {
        let agent_platform = config.platform.clone();
        let skill_platform = if SKILL_PLATFORMS.contains(&agent_platform.as_str()) {
            agent_platform.clone()
        } else {
            "claude-code".to_string()
        };

        App {
            config,
            tab: Tab::Agents,
            input_mode: InputMode::Normal,
            agents: vec![],
            skills: vec![],
            config_fields: vec![],
            list_index: 0,
            active_agent_platform: agent_platform,
            active_skill_platform: skill_platform,
            platform_cursor: 0,
            filter_query: String::new(),
            show_no_deploy: false,
            sort_col: SortColumn::State,
            popup: None,
            output: String::new(),
            output_scroll: 0,
            config_edit_index: 0,
            config_edit_value: String::new(),
            config_dirty: false,
            status_msg: None,
            loading: false,
            error: None,
            should_quit: false,
        }
    }

    pub fn current_platform(&self) -> &str {
        match self.tab {
            Tab::Agents => &self.active_agent_platform,
            Tab::Skills => &self.active_skill_platform,
            Tab::Config => "",
        }
    }

    pub fn set_agents(&mut self, agents: Vec<AgentManifest>) {
        self.agents = agents;
        self.clamp_index();
    }

    pub fn set_skills(&mut self, skills: Vec<SkillManifest>) {
        self.skills = skills;
        self.clamp_index();
    }

    pub fn load_config_fields(&mut self) {
        self.config_fields = load_config_fields();
    }

    pub fn move_up(&mut self) {
        if self.list_index > 0 {
            self.list_index -= 1;
        }
    }

    pub fn move_down(&mut self, max: usize) {
        if max > 0 && self.list_index + 1 < max {
            self.list_index += 1;
        }
    }

    pub fn clamp_index(&mut self) {
        let max = match self.tab {
            Tab::Agents => self.agents.len(),
            Tab::Skills => self.skills.len(),
            Tab::Config => self.config_fields.len(),
        };
        if max == 0 {
            self.list_index = 0;
        } else if self.list_index >= max {
            self.list_index = max - 1;
        }
    }

    pub fn cycle_sort(&mut self) {
        self.sort_col = self.sort_col.next();
    }

    pub fn toggle_no_deploy(&mut self) {
        self.show_no_deploy = !self.show_no_deploy;
    }

    pub fn set_status(&mut self, msg: impl Into<String>) {
        self.status_msg = Some(msg.into());
    }

    pub fn clear_status(&mut self) {
        self.status_msg = None;
    }
}
