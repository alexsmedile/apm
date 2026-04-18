#!/usr/bin/env python3
import argparse
import curses
import json
import locale
import os
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


STATUS_ORDER = {
    "invalid": 0,
    "collision": 1,
    "unmanaged": 2,
    "outdated": 3,
    "ready": 4,
    "orphan": 5,
    "installed": 6,
    "linked": 7,
    "in-sync": 8,
    "not-pushed": 9,
    "no-deploy": 10,
}

STATUS_SYMBOL = {
    "installed": "✓",
    "linked": "↗",
    "in-sync": "✓",
    "outdated": "~",
    "ready": "○",
    "not-pushed": "○",
    "unmanaged": "!",
    "invalid": "x",
    "collision": "x",
    "orphan": "?",
    "no-deploy": "-",
}

CURRENT_STATES = {"installed", "linked", "in-sync"}
ACTIONABLE_STATES = {"ready", "outdated", "not-pushed"}
INVALID_STATES = {"invalid", "collision"}
TAB_ORDER = ["agents", "skills", "settings"]
COMPACT_LIMIT = 12


@dataclass
class TabState:
    selected: int = 0
    scroll: int = 0
    filter_query: str = ""
    expanded: bool = False
    show_no_deploy: bool = True


@dataclass
class AppState:
    helper: str
    active_tab: str
    agents_db: str
    skills_db: str
    platform: str
    scope: str
    runtime_dir: str
    agents_github_mode: str
    skills_github_mode: str
    tabs: Dict[str, TabState] = field(default_factory=lambda: {name: TabState() for name in TAB_ORDER})
    footer: str = "Python TUI preview. Browse is stable; direct actions stay on the CLI for now."


def run_helper(helper: str, args: List[str]) -> dict:
    proc = subprocess.run(
        [sys.executable, helper] + args,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "helper failed")
    return json.loads(proc.stdout)


def normalize_items(tab: str, payload: dict) -> List[dict]:
    items = payload.get("agents") if tab == "agents" else payload.get("skills")
    items = items or payload.get("agents") or payload.get("skills") or []
    items.sort(key=lambda a: (STATUS_ORDER.get((a.get("state") or {}).get("sync", ""), 99), a.get("id", "")))
    return items


def load_items(state: AppState, tab: str) -> List[dict]:
    if tab == "agents":
        if not state.agents_db:
            return []
        payload = run_helper(
            state.helper,
            ["status-agents", "--db", state.agents_db, "--platform", state.platform, "--runtime-dir", state.runtime_dir],
        )
    elif tab == "skills":
        if not state.skills_db:
            return []
        payload = run_helper(
            state.helper,
            ["status-skills", "--db", state.skills_db, "--platform", state.platform, "--runtime-dir", state.runtime_dir],
        )
    else:
        return []
    return normalize_items(tab, payload)


def crop(text: str, width: int) -> str:
    text = str(text or "")
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return text[:1]
    return text[: width - 1] + "…"


def visible_items(items: List[dict], tab_state: TabState) -> Tuple[List[dict], int]:
    rows = items
    if not tab_state.show_no_deploy:
        rows = [item for item in rows if (item.get("state") or {}).get("sync") != "no-deploy"]

    query = tab_state.filter_query.strip().lower()
    if query:
        def matches(item: dict) -> bool:
            root = item.get("root_meta") or {}
            deploy = item.get("deploy") or {}
            fields = [
                item.get("id", ""),
                root.get("name", ""),
                root.get("description", ""),
                deploy.get("name", ""),
                deploy.get("description", ""),
            ]
            return query in " ".join(str(f or "") for f in fields).lower()
        rows = [item for item in rows if matches(item)]

    if tab_state.expanded or len(rows) <= COMPACT_LIMIT:
        return rows, 0

    visible: List[dict] = []
    used: set[int] = set()
    seen_states: set[str] = set()
    for idx, item in enumerate(rows):
        sync = (item.get("state") or {}).get("sync", "?")
        if sync in seen_states:
            continue
        visible.append(item)
        used.add(idx)
        seen_states.add(sync)
        if len(visible) >= COMPACT_LIMIT:
            break

    if len(visible) < COMPACT_LIMIT:
        for idx, item in enumerate(rows):
            if idx in used:
                continue
            visible.append(item)
            if len(visible) >= COMPACT_LIMIT:
                break

    visible.sort(key=lambda a: (STATUS_ORDER.get((a.get("state") or {}).get("sync", ""), 99), a.get("id", "")))
    return visible, max(0, len(rows) - len(visible))


def clamp_selection(tab_state: TabState, count: int) -> None:
    if count <= 0:
        tab_state.selected = 0
        tab_state.scroll = 0
        return
    if tab_state.selected >= count:
        tab_state.selected = count - 1
    if tab_state.selected < 0:
        tab_state.selected = 0
    if tab_state.scroll > tab_state.selected:
        tab_state.scroll = tab_state.selected
    if tab_state.scroll < 0:
        tab_state.scroll = 0


def ensure_visible(tab_state: TabState, viewport_rows: int, count: int) -> None:
    clamp_selection(tab_state, count)
    if viewport_rows <= 0 or count <= 0:
        tab_state.scroll = 0
        return
    if tab_state.selected < tab_state.scroll:
        tab_state.scroll = tab_state.selected
    elif tab_state.selected >= tab_state.scroll + viewport_rows:
        tab_state.scroll = tab_state.selected - viewport_rows + 1
    max_scroll = max(0, count - viewport_rows)
    if tab_state.scroll > max_scroll:
        tab_state.scroll = max_scroll


def setup_colors() -> Dict[str, int]:
    colors = {
        "default": curses.A_NORMAL,
        "selected": curses.A_REVERSE | curses.A_BOLD,
        "title": curses.A_BOLD,
        "dim": curses.A_DIM,
    }
    if not curses.has_colors():
        return colors
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)
    curses.init_pair(2, curses.COLOR_YELLOW, -1)
    curses.init_pair(3, curses.COLOR_CYAN, -1)
    curses.init_pair(4, curses.COLOR_RED, -1)
    curses.init_pair(5, curses.COLOR_WHITE, -1)
    colors.update(
        {
            "green": curses.color_pair(1),
            "yellow": curses.color_pair(2),
            "cyan": curses.color_pair(3),
            "red": curses.color_pair(4),
            "white": curses.color_pair(5),
        }
    )
    return colors


def status_attr(sync: str, colors: Dict[str, int]) -> int:
    if sync in ("installed", "linked", "in-sync"):
        return colors.get("green", curses.A_NORMAL)
    if sync in ("ready", "not-pushed"):
        return colors.get("cyan", curses.A_NORMAL)
    if sync in ("outdated", "unmanaged"):
        return colors.get("yellow", curses.A_NORMAL)
    if sync in ("invalid", "collision", "orphan"):
        return colors.get("red", curses.A_NORMAL) | curses.A_BOLD
    if sync == "no-deploy":
        return colors.get("dim", curses.A_DIM)
    return curses.A_NORMAL


def summary_text(items: List[dict]) -> str:
    current = sum(1 for item in items if (item.get("state") or {}).get("sync") in CURRENT_STATES)
    actionable = sum(1 for item in items if (item.get("state") or {}).get("sync") in ACTIONABLE_STATES)
    invalid = sum(1 for item in items if (item.get("state") or {}).get("sync") in INVALID_STATES)
    return f"Summary      {len(items)} total, {current} current, {actionable} actionable, {invalid} invalid"


def draw_tabs(win, active_tab: str, colors: Dict[str, int], width: int) -> int:
    x = 2
    for tab in TAB_ORDER:
        label = f"[{tab}]"
        attr = colors["selected"] if tab == active_tab else colors["dim"]
        win.addnstr(1, x, label, max(0, width - x - 1), attr)
        x += len(label) + 1
    return 3


def draw_list_pane(win, rows: List[dict], hidden: int, tab: str, state: AppState, colors: Dict[str, int], width: int, height: int) -> None:
    tab_state = state.tabs[tab]
    selected_item = rows[tab_state.selected] if rows else None
    header_lines = [
        f"{tab.capitalize()}",
        "",
        summary_text(rows if tab_state.expanded else rows + []),
        "",
    ]

    # Recompute summary against the filtered set, not only the visible compact slice.
    all_items = load_items(state, tab)
    filtered_all, _ = visible_items(all_items, TabState(
        selected=tab_state.selected,
        scroll=tab_state.scroll,
        filter_query=tab_state.filter_query,
        expanded=True,
        show_no_deploy=tab_state.show_no_deploy,
    ))
    header_lines[2] = summary_text(filtered_all)

    y = 1
    for line in header_lines:
        if y >= height - 1:
            return
        attr = colors["title"] if line == f"{tab.capitalize()}" else curses.A_NORMAL
        win.addnstr(y, 1, crop(line, width - 2), width - 2, attr)
        y += 1

    list_rows = max(1, height - y - (2 if hidden else 1))
    ensure_visible(tab_state, list_rows, len(rows))
    start = tab_state.scroll
    end = min(len(rows), start + list_rows)
    for idx in range(start, end):
        item = rows[idx]
        sync = (item.get("state") or {}).get("sync", "?")
        sym = STATUS_SYMBOL.get(sync, "?")
        text = f" {sym}  {item.get('id', '?'):<28} {sync}"
        attr = status_attr(sync, colors)
        if idx == tab_state.selected:
            attr = colors["selected"]
        if y < height - 1:
            win.addnstr(y, 1, crop(text, width - 2), width - 2, attr)
            y += 1

    if hidden and y < height - 1:
        win.addnstr(y, 1, crop(f"... {hidden} more hidden. Press e to expand.", width - 2), width - 2, colors["dim"])


def detail_lines(tab: str, item: Optional[dict], state: AppState) -> List[str]:
    if tab == "settings":
        return [
            "Settings",
            "",
            f"Default mode : {os.environ.get('APM_TUI_DEFAULT_MODE', 'agents')}",
            f"Agents db    : {state.agents_db or '<not set>'}",
            f"Skills db    : {state.skills_db or '<not set>'}",
            f"Platform     : {state.platform}",
            f"Scope        : {state.scope}",
            f"Runtime      : {state.runtime_dir}",
            f"Agents GitHub: {state.agents_github_mode or 'disabled'}",
            f"Skills GitHub: {state.skills_github_mode or 'disabled'}",
            "",
            "Interactive settings editing is not implemented yet.",
        ]

    lines = [
        "Context",
        "",
        f"Mode       {tab}",
    ]
    if tab == "agents":
        lines.extend(
            [
                f"Platform   {state.platform}",
                f"Scope      {state.scope}",
                f"Runtime    {state.runtime_dir}",
                f"Library    {state.agents_db or '<not set>'}",
                f"GitHub     {state.agents_github_mode or 'disabled'}",
                f"Filter     {state.tabs[tab].filter_query or 'none'}",
            ]
        )
    else:
        lines.extend(
            [
                f"Library    {state.skills_db or '<not set>'}",
                f"GitHub     {state.skills_github_mode or 'disabled'}",
                f"Filter     {state.tabs[tab].filter_query or 'none'}",
            ]
        )

    lines.extend(["", "Selected", ""])
    if not item:
        lines.append("No entry selected.")
        return lines

    root = item.get("root_meta") or {}
    deploy = item.get("deploy") or {}
    sync = (item.get("state") or {}).get("sync", "-")
    lines.extend(
        [
            f"ID         {item.get('id', '-')}",
            f"Name       {root.get('name') or deploy.get('name') or '-'}",
            f"Status     {sync}",
            f"Desc       {root.get('description') or deploy.get('description') or '-'}",
        ]
    )
    if tab == "agents":
        lines.extend(
            [
                f"Deploy     {deploy.get('name') or '-'}",
                f"Links      {len(item.get('links') or [])} tracked",
                "",
                "Actions",
                "",
                "Direct actions move back to the CLI during migration.",
                "Use ':' commands in legacy mode or run CLI commands directly.",
            ]
        )
    else:
        lines.extend(
            [
                "",
                "Actions",
                "",
                "Browse, filter, and inspect only in this first TUI slice.",
            ]
        )
    return lines


def prompt_text(stdscr, prompt: str) -> str:
    height, width = stdscr.getmaxyx()
    curses.echo()
    curses.curs_set(1)
    stdscr.move(height - 1, 0)
    stdscr.clrtoeol()
    stdscr.addnstr(height - 1, 0, prompt, width - 1)
    stdscr.refresh()
    value = stdscr.getstr(height - 1, min(len(prompt), width - 1), max(1, width - len(prompt) - 1))
    curses.noecho()
    curses.curs_set(0)
    return value.decode(errors="ignore")


def render(stdscr, state: AppState, colors: Dict[str, int]) -> None:
    stdscr.erase()
    height, width = stdscr.getmaxyx()
    stdscr.addnstr(0, 2, "apm  interactive", width - 4, colors["title"])
    draw_tabs(stdscr, state.active_tab, colors, width)

    content_top = 4
    footer_y = height - 2
    content_height = max(3, footer_y - content_top)

    if width >= 100:
        left_width = max(36, min(54, int(width * 0.45)))
        right_x = left_width + 2
        right_width = max(20, width - right_x - 2)
        list_win = stdscr.derwin(content_height, left_width, content_top, 1)
        detail_win = stdscr.derwin(content_height, right_width, content_top, right_x)
        if right_x - 1 < width:
            for y in range(content_top, content_top + content_height):
                stdscr.addch(y, right_x - 1, curses.ACS_VLINE)
    else:
        top_height = max(8, content_height // 2)
        bottom_height = max(3, content_height - top_height - 1)
        list_win = stdscr.derwin(top_height, width - 2, content_top, 1)
        detail_win = stdscr.derwin(bottom_height, width - 2, content_top + top_height + 1, 1)
        if content_top + top_height < footer_y:
            stdscr.hline(content_top + top_height, 1, curses.ACS_HLINE, max(1, width - 2))

    if state.active_tab == "settings":
        rows = []
        hidden = 0
        selected = None
    else:
        items = load_items(state, state.active_tab)
        rows, hidden = visible_items(items, state.tabs[state.active_tab])
        clamp_selection(state.tabs[state.active_tab], len(rows))
        selected = rows[state.tabs[state.active_tab].selected] if rows else None
        draw_list_pane(list_win, rows, hidden, state.active_tab, state, colors, list_win.getmaxyx()[1], list_win.getmaxyx()[0])

    detail_win.erase()
    d_height, d_width = detail_win.getmaxyx()
    lines = detail_lines(state.active_tab, selected, state)
    for idx, line in enumerate(lines[: max(0, d_height - 1)]):
        attr = colors["title"] if line in ("Context", "Selected", "Actions", "Settings") else curses.A_NORMAL
        detail_win.addnstr(idx + 1, 1, crop(line, d_width - 2), d_width - 2, attr)
    detail_win.noutrefresh()
    list_win.noutrefresh()

    if state.active_tab == "agents":
        keys = "Tab cycle  1 agents  2 skills  S settings  ↑/↓ or j/k move  e expand  d no-deploy  / filter  q quit"
    elif state.active_tab == "skills":
        keys = "Tab cycle  1 agents  2 skills  S settings  ↑/↓ or j/k move  e expand  d no-deploy  / filter  q quit"
    else:
        keys = "Tab cycle  1 agents  2 skills  S settings  q quit"

    stdscr.addnstr(height - 2, 1, crop(keys, width - 2), width - 2, colors["dim"])
    stdscr.addnstr(height - 1, 1, crop(state.footer, width - 2), width - 2, colors["dim"])
    curses.doupdate()


def move_selection(state: AppState, delta: int) -> None:
    tab_state = state.tabs[state.active_tab]
    if state.active_tab == "settings":
        return
    items = load_items(state, state.active_tab)
    rows, _ = visible_items(items, tab_state)
    clamp_selection(tab_state, len(rows))
    if not rows:
        return
    tab_state.selected = max(0, min(len(rows) - 1, tab_state.selected + delta))
    state.footer = f"Selected {rows[tab_state.selected].get('id', '?')}"


def next_tab(current: str) -> str:
    idx = TAB_ORDER.index(current)
    return TAB_ORDER[(idx + 1) % len(TAB_ORDER)]


def main_loop(stdscr, state: AppState) -> None:
    locale.setlocale(locale.LC_ALL, "")
    curses.curs_set(0)
    stdscr.keypad(True)
    colors = setup_colors()

    while True:
        try:
            render(stdscr, state, colors)
        except Exception as exc:
            state.footer = f"Render error: {exc}"
            render(stdscr, state, colors)

        key = stdscr.get_wch()
        if key in ("q", "Q"):
            return
        if key == "\t":
            state.active_tab = next_tab(state.active_tab)
            state.footer = f"Switched to {state.active_tab}"
            continue
        if key == "1":
            state.active_tab = "agents"
            state.footer = "Switched to agents"
            continue
        if key == "2":
            state.active_tab = "skills"
            state.footer = "Switched to skills"
            continue
        if key == "S":
            state.active_tab = "settings"
            state.footer = "Switched to settings"
            continue
        if key in (curses.KEY_UP, "k"):
            move_selection(state, -1)
            continue
        if key in (curses.KEY_DOWN, "j"):
            move_selection(state, 1)
            continue
        if key == curses.KEY_RESIZE:
            state.footer = "Resized"
            continue
        if key == "e" and state.active_tab != "settings":
            tab_state = state.tabs[state.active_tab]
            tab_state.expanded = not tab_state.expanded
            state.footer = "Expanded view" if tab_state.expanded else "Compact view"
            continue
        if key == "d" and state.active_tab != "settings":
            tab_state = state.tabs[state.active_tab]
            tab_state.show_no_deploy = not tab_state.show_no_deploy
            tab_state.selected = 0
            tab_state.scroll = 0
            state.footer = "Showing no-deploy" if tab_state.show_no_deploy else "Hiding no-deploy"
            continue
        if key == "/" and state.active_tab != "settings":
            value = prompt_text(stdscr, "filter> ")
            tab_state = state.tabs[state.active_tab]
            tab_state.filter_query = value
            tab_state.selected = 0
            tab_state.scroll = 0
            state.footer = f"Filter: {value or 'none'}"
            continue
        if key in ("\n", curses.KEY_ENTER, "\r"):
            state.footer = "Details are shown in the right pane."
            continue
        state.footer = f"Key not handled: {key!r}"


def build_state(helper: str) -> AppState:
    initial_tab = os.environ.get("APM_TUI_MODE") or os.environ.get("APM_TUI_DEFAULT_MODE") or "agents"
    if initial_tab not in TAB_ORDER:
        initial_tab = "agents"
    return AppState(
        helper=helper,
        active_tab=initial_tab,
        agents_db=os.environ.get("APM_TUI_AGENTS_DB", ""),
        skills_db=os.environ.get("APM_TUI_SKILLS_DB", ""),
        platform=os.environ.get("APM_TUI_PLATFORM", "claude-code"),
        scope=os.environ.get("APM_TUI_SCOPE", "global"),
        runtime_dir=os.environ.get("APM_TUI_RUNTIME_DIR", ""),
        agents_github_mode=os.environ.get("APM_TUI_AGENTS_GITHUB_MODE", ""),
        skills_github_mode=os.environ.get("APM_TUI_SKILLS_GITHUB_MODE", ""),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="apm Python curses TUI")
    parser.add_argument("--helper", required=True, help="Path to apm_python.py")
    args = parser.parse_args()
    state = build_state(args.helper)
    curses.wrapper(main_loop, state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
