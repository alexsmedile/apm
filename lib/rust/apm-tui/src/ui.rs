use crate::app::{App, InputMode, Tab, AGENT_PLATFORMS, SKILL_PLATFORMS};
use crate::filter::{filter_agents, filter_skills, sort_agents, sort_skills, SortColumn};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{
        Block, Borders, Cell, Clear, List, ListItem, ListState, Paragraph, Row, Table, TableState,
        Wrap,
    },
    Frame,
};
use std::env;

pub fn draw(f: &mut Frame, app: &App) {
    let area = f.area();

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1), // tab bar
            Constraint::Length(1), // status bar
            Constraint::Min(1),    // content
            Constraint::Length(1), // footer
        ])
        .split(area);

    draw_tabs(f, app, chunks[0]);
    draw_statusbar(f, app, chunks[1]);

    match app.tab {
        Tab::Agents => draw_agents(f, app, chunks[2]),
        Tab::Skills => draw_skills(f, app, chunks[2]),
        Tab::Config => draw_config(f, app, chunks[2]),
    }

    draw_footer(f, app, chunks[3]);

    // Overlays
    if let Some(popup) = &app.popup {
        draw_popup(f, popup, area);
    } else if app.input_mode == InputMode::PlatformSelect {
        draw_platform_select(f, app, area);
    } else if app.input_mode == InputMode::OutputPane {
        draw_output(f, app, area);
    }
}

fn draw_tabs(f: &mut Frame, app: &App, area: Rect) {
    let tabs = vec![
        (" Agents ", Tab::Agents),
        (" Skills ", Tab::Skills),
        (" Config ", Tab::Config),
    ];
    let mut spans: Vec<Span> = vec![Span::raw(" ")];
    for (label, tab) in &tabs {
        let style = if app.tab == *tab {
            Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::DarkGray)
        };
        spans.push(Span::styled(format!("[{}]", label.trim()), style));
        spans.push(Span::raw(" "));
    }
    if app.loading {
        spans.push(Span::styled(" loading…", Style::default().fg(Color::Yellow)));
    }
    if let Some(err) = &app.error {
        spans.push(Span::styled(
            format!(" ⚠ {}", err),
            Style::default().fg(Color::Red),
        ));
    }
    let line = Line::from(spans);
    f.render_widget(Paragraph::new(line), area);
}

fn draw_statusbar(f: &mut Frame, app: &App, area: Rect) {
    let cwd = env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    let platform = app.current_platform();
    let scope = &app.config.scope;
    let mode = match app.tab {
        Tab::Agents => "agents",
        Tab::Skills => "skills",
        Tab::Config => "config",
    };

    let mut parts = vec![
        Span::styled(format!(" Mode:{} ", mode), Style::default().fg(Color::Cyan)),
        Span::raw("│"),
    ];
    if !platform.is_empty() {
        parts.push(Span::styled(
            format!(" Platform:{} ", platform),
            Style::default().fg(Color::Green),
        ));
        parts.push(Span::raw("│"));
    }
    parts.push(Span::styled(
        format!(" Scope:{} ", scope),
        Style::default().fg(Color::Blue),
    ));
    parts.push(Span::raw("│"));
    parts.push(Span::styled(
        format!(" CWD:{} ", cwd),
        Style::default().fg(Color::DarkGray),
    ));

    if let Some(msg) = &app.status_msg {
        parts.push(Span::raw(" │ "));
        parts.push(Span::styled(msg.as_str(), Style::default().fg(Color::Yellow)));
    }

    f.render_widget(
        Paragraph::new(Line::from(parts))
            .style(Style::default().bg(Color::Black)),
        area,
    );
}

fn draw_agents(f: &mut Frame, app: &App, area: Rect) {
    let mut visible: Vec<&_> = filter_agents(&app.agents, &app.filter_query, app.show_no_deploy);
    sort_agents(&mut visible, &app.sort_col);

    let header_cells = agent_header_cells(&app.sort_col);
    let header = Row::new(header_cells)
        .style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = visible
        .iter()
        .map(|a| {
            let state = a.sync_state();
            let state_style = state_color(state);
            Row::new(vec![
                Cell::from(a.id.clone()),
                Cell::from(state).style(state_style),
                Cell::from(a.platform().to_string()),
                Cell::from(a.category.clone()),
            ])
        })
        .collect();

    let mut ts = TableState::default();
    if !visible.is_empty() {
        ts.select(Some(app.list_index.min(visible.len().saturating_sub(1))));
    }

    let filter_info = filter_bar_text(app);
    let title = format!(" Agents ({}) {}", visible.len(), filter_info);

    let table = Table::new(
        rows,
        [
            Constraint::Percentage(35),
            Constraint::Percentage(15),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ],
    )
    .header(header)
    .block(Block::default().borders(Borders::ALL).title(title))
    .row_highlight_style(Style::default().bg(Color::DarkGray).add_modifier(Modifier::BOLD))
    .highlight_symbol("> ");

    f.render_stateful_widget(table, area, &mut ts);
}

fn draw_skills(f: &mut Frame, app: &App, area: Rect) {
    let mut visible: Vec<&_> = filter_skills(&app.skills, &app.filter_query, app.show_no_deploy);
    sort_skills(&mut visible, &app.sort_col);

    let header_cells = skill_header_cells(&app.sort_col);
    let header = Row::new(header_cells)
        .style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = visible
        .iter()
        .map(|s| {
            let state = s.sync_state();
            let state_style = state_color(state);
            Row::new(vec![
                Cell::from(s.id.clone()),
                Cell::from(state).style(state_style),
                Cell::from(s.platform().to_string()),
                Cell::from(s.description().chars().take(40).collect::<String>()),
            ])
        })
        .collect();

    let mut ts = TableState::default();
    if !visible.is_empty() {
        ts.select(Some(app.list_index.min(visible.len().saturating_sub(1))));
    }

    let filter_info = filter_bar_text(app);
    let title = format!(" Skills ({}) {}", visible.len(), filter_info);

    let table = Table::new(
        rows,
        [
            Constraint::Percentage(30),
            Constraint::Percentage(15),
            Constraint::Percentage(20),
            Constraint::Percentage(35),
        ],
    )
    .header(header)
    .block(Block::default().borders(Borders::ALL).title(title))
    .row_highlight_style(Style::default().bg(Color::DarkGray).add_modifier(Modifier::BOLD))
    .highlight_symbol("> ");

    f.render_stateful_widget(table, area, &mut ts);
}

fn draw_config(f: &mut Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .config_fields
        .iter()
        .enumerate()
        .map(|(i, field)| {
            let marker = if app.config_edit_index == i
                && app.input_mode == InputMode::ConfigEdit
            {
                "▶ "
            } else {
                "  "
            };
            let val = if app.config_edit_index == i
                && app.input_mode == InputMode::ConfigEdit
            {
                app.config_edit_value.clone()
            } else {
                field.value.clone()
            };
            let edit_hint = if field.editable { "" } else { " (read-only)" };
            let content = format!(
                "{}{:<20} = {}{}",
                marker, field.label, val, edit_hint
            );
            ListItem::new(content)
        })
        .collect();

    let title = if app.config_dirty {
        " Config  [unsaved changes — press w to save] "
    } else {
        " Config "
    };

    let mut ls = ListState::default();
    ls.select(Some(app.config_edit_index));

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(title))
        .highlight_style(Style::default().bg(Color::DarkGray).add_modifier(Modifier::BOLD))
        .highlight_symbol("> ");

    f.render_stateful_widget(list, area, &mut ls);
}

fn draw_footer(f: &mut Frame, app: &App, area: Rect) {
    let text = match app.input_mode {
        InputMode::Filter => {
            format!(" Filter: {}█  [Esc] cancel  [Enter] apply", app.filter_query)
        }
        InputMode::ConfigEdit => {
            format!(" Edit: {}█  [Esc] cancel  [Enter] confirm  [w] save", app.config_edit_value)
        }
        InputMode::Normal => match app.tab {
            Tab::Agents | Tab::Skills => {
                let nd = if app.show_no_deploy { "hide no-deploy" } else { "show no-deploy" };
                format!(
                    " [/] filter  [s] sort:{}  [p] platform  [d] {}  [r] reload  [Tab] tab  [Enter] actions  [q] quit",
                    app.sort_col.label(),
                    nd
                )
            }
            Tab::Config => {
                " [↑↓] navigate  [Enter] edit  [w] save  [Tab] tab  [q] quit".to_string()
            }
        },
        InputMode::PlatformSelect => {
            " [↑↓] select  [Enter] apply  [P] save to config  [Esc] cancel".to_string()
        }
        InputMode::ActionPopup => {
            " [↑↓] select  [Enter] run  [Esc] cancel".to_string()
        }
        InputMode::OutputPane => {
            " [↑↓/j/k] scroll  [Esc/q] close  [r] reload data".to_string()
        }
    };

    f.render_widget(
        Paragraph::new(text).style(Style::default().fg(Color::DarkGray)),
        area,
    );
}

pub fn draw_popup(f: &mut Frame, popup: &crate::actions::AgentPopup, area: Rect) {
    let width = 36u16;
    let height = (popup.actions.len() as u16) + 4;
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    let popup_area = Rect::new(x, y, width.min(area.width), height.min(area.height));

    f.render_widget(Clear, popup_area);

    let title = format!("  {}  [{}]  ", popup.id, popup.state);
    let items: Vec<ListItem> = popup
        .actions
        .iter()
        .enumerate()
        .map(|(i, action)| {
            let style = if i == popup.selected {
                Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            ListItem::new(format!("  {}  ", action.label())).style(style)
        })
        .collect();

    let mut ls = ListState::default();
    ls.select(Some(popup.selected));

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(title)
                .title_alignment(Alignment::Center),
        )
        .highlight_symbol("> ");

    f.render_stateful_widget(list, popup_area, &mut ls);
}

fn draw_platform_select(f: &mut Frame, app: &App, area: Rect) {
    let platforms: &[&str] = match app.tab {
        Tab::Skills => SKILL_PLATFORMS,
        _ => AGENT_PLATFORMS,
    };

    let width = 28u16;
    let height = (platforms.len() as u16) + 2;
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + 2;
    let popup_area = Rect::new(x, y, width.min(area.width), height.min(area.height));

    f.render_widget(Clear, popup_area);

    let items: Vec<ListItem> = platforms
        .iter()
        .enumerate()
        .map(|(i, p)| {
            let style = if i == app.platform_cursor {
                Style::default().fg(Color::Black).bg(Color::Green).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            ListItem::new(format!("  {}  ", p)).style(style)
        })
        .collect();

    let mut ls = ListState::default();
    ls.select(Some(app.platform_cursor));

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Select Platform "));

    f.render_stateful_widget(list, popup_area, &mut ls);
}

fn draw_output(f: &mut Frame, app: &App, area: Rect) {
    let width = area.width.saturating_sub(4);
    let height = area.height.saturating_sub(4);
    let popup_area = Rect::new(area.x + 2, area.y + 2, width, height);

    f.render_widget(Clear, popup_area);

    let paragraph = Paragraph::new(app.output.as_str())
        .block(Block::default().borders(Borders::ALL).title(" Output  [Esc] close "))
        .wrap(Wrap { trim: false })
        .scroll((app.output_scroll as u16, 0));

    f.render_widget(paragraph, popup_area);
}

fn agent_header_cells(sort: &SortColumn) -> Vec<Cell<'static>> {
    vec![
        header_cell("ID", matches!(sort, SortColumn::Name)),
        header_cell("State", matches!(sort, SortColumn::State)),
        header_cell("Platform", matches!(sort, SortColumn::Platform)),
        header_cell("Category", matches!(sort, SortColumn::Category)),
    ]
}

fn skill_header_cells(sort: &SortColumn) -> Vec<Cell<'static>> {
    vec![
        header_cell("ID", matches!(sort, SortColumn::Name)),
        header_cell("State", matches!(sort, SortColumn::State)),
        header_cell("Platform", matches!(sort, SortColumn::Platform)),
        header_cell("Description", false),
    ]
}

fn header_cell(label: &'static str, active: bool) -> Cell<'static> {
    if active {
        Cell::from(format!("{} ▲", label))
            .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
    } else {
        Cell::from(label).style(Style::default().fg(Color::White))
    }
}

fn filter_bar_text(app: &App) -> String {
    if !app.filter_query.is_empty() {
        format!("[filter: {}]", app.filter_query)
    } else {
        String::new()
    }
}

pub fn state_color(state: &str) -> Style {
    match state {
        "installed" | "linked" => Style::default().fg(Color::Green),
        "ready" => Style::default().fg(Color::Cyan),
        "outdated" | "unmanaged" => Style::default().fg(Color::Yellow),
        "invalid" | "orphan" | "collision" => Style::default().fg(Color::Red),
        "no-deploy" => Style::default().fg(Color::DarkGray),
        _ => Style::default(),
    }
}
