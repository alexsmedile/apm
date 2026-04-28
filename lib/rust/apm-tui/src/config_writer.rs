use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

#[derive(Clone)]
pub struct ConfigField {
    pub key: String,
    pub value: String,
    pub label: String,
    pub editable: bool,
}

pub fn config_path() -> PathBuf {
    let config_dir = std::env::var("APM_CONFIG_DIR")
        .unwrap_or_else(|_| {
            std::env::var("HOME")
                .map(|h| format!("{}/.config/apm", h))
                .unwrap_or_default()
        });
    PathBuf::from(config_dir).join("config.sh")
}

pub fn load_config_fields() -> Vec<ConfigField> {
    let path = config_path();
    let content = fs::read_to_string(&path).unwrap_or_default();

    let keys = vec![
        ("APM_PLATFORM", "Default Platform", true),
        ("APM_DEFAULT_MODE", "Default Mode", true),
        ("AGENTS_DB", "Agents DB Path", true),
        ("SKILLS_DB", "Skills DB Path", true),
        ("APM_CONFIG_DIR", "Config Dir", false),
    ];

    keys.into_iter()
        .map(|(key, label, editable)| {
            let value = extract_value(&content, key).unwrap_or_default();
            ConfigField { key: key.to_string(), value, label: label.to_string(), editable }
        })
        .collect()
}

fn extract_value(content: &str, key: &str) -> Option<String> {
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix(&format!("{}=", key)) {
            return Some(rest.trim_matches('"').trim_matches('\'').to_string());
        }
        if let Some(rest) = trimmed.strip_prefix(&format!("export {}=", key)) {
            return Some(rest.trim_matches('"').trim_matches('\'').to_string());
        }
    }
    // Fall back to env
    std::env::var(key).ok()
}

pub fn save_field(key: &str, value: &str) -> Result<()> {
    let path = config_path();
    let content = fs::read_to_string(&path).unwrap_or_default();

    let new_line = format!("{}=\"{}\"", key, value);
    let mut found = false;
    let mut new_lines: Vec<String> = content
        .lines()
        .map(|line| {
            let trimmed = line.trim();
            if trimmed.starts_with(&format!("{}=", key))
                || trimmed.starts_with(&format!("export {}=", key))
            {
                found = true;
                new_line.clone()
            } else {
                line.to_string()
            }
        })
        .collect();

    if !found {
        new_lines.push(new_line);
    }

    // Ensure parent dir exists
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).context("failed to create config dir")?;
    }

    fs::write(&path, new_lines.join("\n") + "\n").context("failed to write config")?;
    Ok(())
}
