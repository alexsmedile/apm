mod actions;
mod app;
mod backend;
mod config_writer;
mod filter;
mod ui;

use actions::{Action, AgentPopup};
use app::{App, InputMode, Tab, AGENT_PLATFORMS, SKILL_PLATFORMS};
use backend::{fetch_agents, fetch_skills, run_apm_command, BackendConfig};
use config_writer::save_field;

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::time::Duration;

fn main() -> Result<()> {
    let config = BackendConfig::from_env();

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::new(config);
    app.load_config_fields();
    load_tab_data(&mut app);

    let result = run_loop(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run_loop(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App) -> Result<()> {
    loop {
        terminal.draw(|f| ui::draw(f, app))?;

        if !event::poll(Duration::from_millis(200))? {
            continue;
        }

        if let Event::Key(key) = event::read()? {
            handle_key(app, key);
        }

        if app.should_quit {
            break;
        }
    }
    Ok(())
}

fn handle_key(app: &mut App, key: KeyEvent) {
    // Ctrl-C always quits
    if key.modifiers == KeyModifiers::CONTROL && key.code == KeyCode::Char('c') {
        app.should_quit = true;
        return;
    }

    match app.input_mode {
        InputMode::Filter => handle_filter(app, key),
        InputMode::PlatformSelect => handle_platform_select(app, key),
        InputMode::ActionPopup => handle_popup(app, key),
        InputMode::OutputPane => handle_output(app, key),
        InputMode::ConfigEdit => handle_config_edit(app, key),
        InputMode::Normal => handle_normal(app, key),
    }
}

fn handle_normal(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Char('q') => app.should_quit = true,
        KeyCode::Tab => {
            app.tab = app.tab.next();
            app.list_index = 0;
            app.filter_query.clear();
            if app.tab == Tab::Config {
                app.load_config_fields();
            } else {
                load_tab_data(app);
            }
        }
        KeyCode::BackTab => {
            app.tab = app.tab.prev();
            app.list_index = 0;
            app.filter_query.clear();
            if app.tab == Tab::Config {
                app.load_config_fields();
            } else {
                load_tab_data(app);
            }
        }
        KeyCode::Up | KeyCode::Char('k') => app.move_up(),
        KeyCode::Down | KeyCode::Char('j') => {
            let max = visible_count(app);
            app.move_down(max);
        }
        KeyCode::Char('/') => {
            app.input_mode = InputMode::Filter;
        }
        KeyCode::Char('s') => app.cycle_sort(),
        KeyCode::Char('d') => app.toggle_no_deploy(),
        KeyCode::Char('r') => load_tab_data(app),
        KeyCode::Char('p') => {
            let platforms: &[&str] = match app.tab {
                Tab::Skills => SKILL_PLATFORMS,
                _ => AGENT_PLATFORMS,
            };
            let current = app.current_platform();
            app.platform_cursor =
                platforms.iter().position(|p| *p == current).unwrap_or(0);
            app.input_mode = InputMode::PlatformSelect;
        }
        KeyCode::Enter => {
            match app.tab {
                Tab::Config => {
                    if let Some(field) = app.config_fields.get(app.config_edit_index) {
                        if field.editable {
                            app.config_edit_value = field.value.clone();
                            app.input_mode = InputMode::ConfigEdit;
                        }
                    }
                }
                _ => open_popup(app),
            }
        }
        KeyCode::Char('w') if app.tab == Tab::Config => save_config(app),
        _ => {}
    }
}

fn handle_filter(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.filter_query.clear();
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Enter => {
            app.list_index = 0;
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Backspace => {
            app.filter_query.pop();
        }
        KeyCode::Char(c) => {
            app.filter_query.push(c);
            app.list_index = 0;
        }
        _ => {}
    }
}

fn handle_platform_select(app: &mut App, key: KeyEvent) {
    let platforms: &[&str] = match app.tab {
        Tab::Skills => SKILL_PLATFORMS,
        _ => AGENT_PLATFORMS,
    };

    match key.code {
        KeyCode::Esc => app.input_mode = InputMode::Normal,
        KeyCode::Up | KeyCode::Char('k') => {
            if app.platform_cursor > 0 {
                app.platform_cursor -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.platform_cursor + 1 < platforms.len() {
                app.platform_cursor += 1;
            }
        }
        KeyCode::Enter => {
            let selected = platforms[app.platform_cursor].to_string();
            match app.tab {
                Tab::Skills => app.active_skill_platform = selected,
                _ => app.active_agent_platform = selected,
            }
            app.input_mode = InputMode::Normal;
            app.list_index = 0;
            load_tab_data(app);
        }
        // Shift-P: save platform to config
        KeyCode::Char('P') => {
            let selected = platforms[app.platform_cursor].to_string();
            if let Err(e) = save_field("APM_PLATFORM", &selected) {
                app.error = Some(format!("save failed: {}", e));
            } else {
                app.set_status(format!("Saved APM_PLATFORM={}", selected));
            }
            match app.tab {
                Tab::Skills => app.active_skill_platform = selected,
                _ => app.active_agent_platform = selected,
            }
            app.input_mode = InputMode::Normal;
            load_tab_data(app);
        }
        _ => {}
    }
}

fn handle_popup(app: &mut App, key: KeyEvent) {
    let popup = match &mut app.popup {
        Some(p) => p,
        None => {
            app.input_mode = InputMode::Normal;
            return;
        }
    };

    match key.code {
        KeyCode::Esc => {
            app.popup = None;
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Up | KeyCode::Char('k') => popup.move_up(),
        KeyCode::Down | KeyCode::Char('j') => popup.move_down(),
        KeyCode::Enter => {
            let action = popup.current_action().clone();
            let id = popup.id.clone();
            let platform = popup.platform.clone();
            app.popup = None;
            app.input_mode = InputMode::Normal;

            if action == Action::Cancel {
                return;
            }

            let args_owned = action.to_apm_args(&id, &platform);
            let args: Vec<&str> = args_owned.iter().map(|s| s.as_str()).collect();
            match run_apm_command(&args) {
                Ok(output) => {
                    app.output = output;
                    app.output_scroll = 0;
                    app.input_mode = InputMode::OutputPane;
                }
                Err(e) => {
                    app.error = Some(format!("command failed: {}", e));
                }
            }
        }
        _ => {}
    }
}

fn handle_output(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc | KeyCode::Char('q') => {
            app.output.clear();
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Char('r') => {
            app.output.clear();
            app.input_mode = InputMode::Normal;
            load_tab_data(app);
        }
        KeyCode::Up | KeyCode::Char('k') => {
            if app.output_scroll > 0 {
                app.output_scroll -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            app.output_scroll += 1;
        }
        _ => {}
    }
}

fn handle_config_edit(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Enter => {
            let idx = app.config_edit_index;
            let val = app.config_edit_value.clone();
            if let Some(field) = app.config_fields.get_mut(idx) {
                field.value = val;
                app.config_dirty = true;
            }
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Backspace => {
            app.config_edit_value.pop();
        }
        KeyCode::Up => {
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Down => {
            app.input_mode = InputMode::Normal;
        }
        KeyCode::Char(c) => match c {
            'k' => app.input_mode = InputMode::Normal,
            'j' => app.input_mode = InputMode::Normal,
            'w' => {
                app.input_mode = InputMode::Normal;
                save_config(app);
            }
            _ => app.config_edit_value.push(c),
        },
        _ => {}
    }
}

fn open_popup(app: &mut App) {
    let platform = app.current_platform().to_string();
    match app.tab {
        Tab::Agents => {
            let visible: Vec<&_> =
                filter::filter_agents(&app.agents, &app.filter_query, app.show_no_deploy)
                    .into_iter()
                    .collect();
            let mut sorted = visible;
            filter::sort_agents(&mut sorted, &app.sort_col);
            if let Some(agent) = sorted.get(app.list_index) {
                app.popup = Some(AgentPopup::for_agent(agent, &platform));
                app.input_mode = InputMode::ActionPopup;
            }
        }
        Tab::Skills => {
            let visible: Vec<&_> =
                filter::filter_skills(&app.skills, &app.filter_query, app.show_no_deploy)
                    .into_iter()
                    .collect();
            let mut sorted = visible;
            filter::sort_skills(&mut sorted, &app.sort_col);
            if let Some(skill) = sorted.get(app.list_index) {
                app.popup = Some(AgentPopup::for_skill(skill, &platform));
                app.input_mode = InputMode::ActionPopup;
            }
        }
        Tab::Config => {}
    }
}

fn save_config(app: &mut App) {
    let fields = app.config_fields.clone();
    let mut errors = vec![];
    for field in &fields {
        if field.editable {
            if let Err(e) = save_field(&field.key, &field.value) {
                errors.push(format!("{}: {}", field.key, e));
            }
        }
    }
    if errors.is_empty() {
        app.config_dirty = false;
        app.set_status("Config saved.");
    } else {
        app.error = Some(errors.join("; "));
    }
}

fn load_tab_data(app: &mut App) {
    app.error = None;
    match app.tab {
        Tab::Agents => {
            let platform = app.active_agent_platform.clone();
            match fetch_agents(&app.config, &platform) {
                Ok(agents) => app.set_agents(agents),
                Err(e) => app.error = Some(format!("agents: {}", e)),
            }
        }
        Tab::Skills => {
            let platform = app.active_skill_platform.clone();
            match fetch_skills(&app.config, &platform) {
                Ok(skills) => app.set_skills(skills),
                Err(e) => app.error = Some(format!("skills: {}", e)),
            }
        }
        Tab::Config => {
            app.load_config_fields();
        }
    }
}

fn visible_count(app: &App) -> usize {
    match app.tab {
        Tab::Agents => {
            filter::filter_agents(&app.agents, &app.filter_query, app.show_no_deploy).len()
        }
        Tab::Skills => {
            filter::filter_skills(&app.skills, &app.filter_query, app.show_no_deploy).len()
        }
        Tab::Config => app.config_fields.len(),
    }
}
