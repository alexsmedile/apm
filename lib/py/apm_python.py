#!/usr/bin/env python3
"""
apm_python.py — Python helper for apm
Handles: YAML/frontmatter parsing, normalization, schema validation,
         manifest generation, structured diff output.
All output is JSON. Shell calls this and consumes JSON.
"""

import json
import os
import re
import sys
import hashlib
import argparse
from datetime import datetime, timezone, date

# ---------------------------------------------------------------------------
# PyYAML import — fail gracefully with JSON error
# ---------------------------------------------------------------------------
try:
    import yaml
except ImportError:
    print(json.dumps({
        "error": "PyYAML not installed. Run: pip3 install pyyaml",
        "exit_code": 3
    }))
    sys.exit(3)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CANONICAL_ID_RE = re.compile(r'^[a-z0-9][a-z0-9-]*$')
IGNORED_DIRS = {'.obsidian', '_imports', '_staging'}

# Short aliases used in instruction file names (e.g. git-mentor.cc@latest.md)
PLATFORM_ALIASES = {
    'claude-code': 'cc',
    'cursor':      'crs',
    'gemini':      'gmn',
    'codex':       'cdx',
    'windsurf':    'wds',
    'continue':    'cnt',
    'agents-dir':  'agt',
    'generic':     'gen',
}

SKILL_SUPPORTED_PLATFORMS = {'claude-code', 'codex', 'windsurf', 'agents-dir'}

# ---------------------------------------------------------------------------
# Frontmatter parsing
# ---------------------------------------------------------------------------

def parse_frontmatter(content: str) -> tuple[dict, str]:
    """
    Parse ---\nYAML\n---\nbody from file content.
    Returns (frontmatter_dict, body_text).
    Raises yaml.YAMLError on bad YAML.
    """
    if not content.startswith('---'):
        return {}, content

    lines = content.split('\n')
    # Find closing ---
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end_idx = i
            break

    if end_idx is None:
        return {}, content

    yaml_text = '\n'.join(lines[1:end_idx])
    body_text = '\n'.join(lines[end_idx + 1:]).lstrip('\n')

    fm = yaml.safe_load(yaml_text) or {}
    return fm, body_text


class _SafeEncoder(json.JSONEncoder):
    """JSON encoder that converts datetime/date to ISO strings."""
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        return super().default(obj)


def _dump(obj) -> str:
    return json.dumps(obj, cls=_SafeEncoder)


def read_file(path: str) -> str:
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


def parse_agent_file(path: str) -> tuple[dict, str]:
    """Read and parse a markdown agent file. Returns (frontmatter, body)."""
    content = read_file(path)
    return parse_frontmatter(content)


# ---------------------------------------------------------------------------
# Normalization helpers
# ---------------------------------------------------------------------------

def normalize_tools(tools) -> list:
    """Normalize tools: cast to list, deduplicate, sort."""
    if tools is None:
        return []
    if isinstance(tools, str):
        tools = [t.strip() for t in tools.split(',')]
    if not isinstance(tools, list):
        tools = list(tools)
    return sorted(set(t.strip() for t in tools if t and str(t).strip()))


def normalize_body(body: str) -> str:
    """Strip trailing whitespace per line, strip surrounding blank lines."""
    lines = [line.rstrip() for line in body.split('\n')]
    # Strip leading blank lines
    while lines and not lines[0]:
        lines.pop(0)
    # Strip trailing blank lines
    while lines and not lines[-1]:
        lines.pop()
    return '\n'.join(lines)


def body_hash(body: str) -> str:
    return hashlib.sha256(normalize_body(body).encode()).hexdigest()


# ---------------------------------------------------------------------------
# Deploy block extraction
# ---------------------------------------------------------------------------

def extract_deploy(fm: dict, platform: str) -> dict:
    """
    Extract and normalize deploy config for given platform.
    Returns normalized dict with: platform, enabled, name, description, model, tools

    agents-dir is a storage location, not a platform variant. If no agents-dir
    block exists, fall back to the first enabled deploy block found (any platform).
    Other platforms with no block return enabled: False (no-deploy).
    """
    deploy_block = fm.get('deploy', {}) or {}
    plat_block = deploy_block.get(platform, {}) or {}

    enabled = plat_block.get('enabled', True)
    if enabled is False:
        return {'platform': platform, 'enabled': False}

    if not plat_block:
        # agents-dir: fall back to first enabled deploy block
        if platform == 'agents-dir':
            for pb in deploy_block.values():
                if isinstance(pb, dict) and pb.get('enabled', True) is not False:
                    plat_block = pb
                    break
        if not plat_block:
            return {'platform': platform, 'enabled': False}

    return {
        'platform': platform,
        'enabled': True,
        'name': plat_block.get('name', ''),
        'description': plat_block.get('description', ''),
        'model': plat_block.get('model', ''),
        'tools': normalize_tools(plat_block.get('tools')),
        'applyTo': plat_block.get('applyTo', plat_block.get('paths', [])) or [],
        'tags': plat_block.get('tags', []) or [],
        # Cursor-specific fields
        'readonly': plat_block.get('readonly', None),
        'is_background': plat_block.get('is_background', None),
    }


# ---------------------------------------------------------------------------
# Library scan
# ---------------------------------------------------------------------------

def scan_library(db_path: str) -> list:
    """Return list of canonical agent IDs found in db_path."""
    if not os.path.isdir(db_path):
        return []

    ids = []
    for entry in sorted(os.listdir(db_path)):
        full = os.path.join(db_path, entry)
        if not os.path.isdir(full):
            continue
        if entry.startswith('_') or entry.startswith('.'):
            continue
        if entry in IGNORED_DIRS:
            continue
        # Candidate: must have <id>/<id>.md
        root_file = os.path.join(full, f'{entry}.md')
        if os.path.isfile(root_file):
            ids.append(entry)
    return ids


def scan_skills(db_path: str) -> list:
    """Return list of canonical skill IDs found in db_path."""
    return [rec['id'] for rec in _scan_skill_records(db_path)]


def _scan_skill_records(db_path: str) -> list[dict]:
    """
    Return skill records discovered in db_path.

    Preferred layout:
      <db>/<repo>/skills/<skill-id>/SKILL.md

    Fallback layout:
      <db>/<skill-id>/SKILL.md
    """
    if not os.path.isdir(db_path):
        return []

    records = []
    for entry in sorted(os.listdir(db_path)):
        full = os.path.join(db_path, entry)
        if not os.path.isdir(full):
            continue
        if entry.startswith('_') or entry.startswith('.'):
            continue
        if entry in IGNORED_DIRS:
            continue

        repo_skills_dir = os.path.join(full, 'skills')
        if os.path.isdir(repo_skills_dir):
            for skill_entry in sorted(os.listdir(repo_skills_dir)):
                skill_dir = os.path.join(repo_skills_dir, skill_entry)
                if not os.path.isdir(skill_dir):
                    continue
                if skill_entry.startswith('_') or skill_entry.startswith('.'):
                    continue
                skill_file = os.path.join(skill_dir, 'SKILL.md')
                if os.path.isfile(skill_file):
                    records.append({
                        'id': skill_entry,
                        'skill_dir': skill_dir,
                        'skill_file': skill_file,
                        'source': 'repo-skills',
                        'repo': entry,
                    })
            continue

        skill_file = os.path.join(full, 'SKILL.md')
        if os.path.isfile(skill_file):
            records.append({
                'id': entry,
                'skill_dir': full,
                'skill_file': skill_file,
                'source': 'direct',
                'repo': '',
            })

    return records


def _skill_record_map(db_path: str) -> dict[str, dict]:
    """Return {skill_id: skill_record} for discovered skills."""
    return {rec['id']: rec for rec in _scan_skill_records(db_path)}


def parse_skill_file(path: str) -> tuple[dict, str]:
    """Read and parse a SKILL.md file. Returns (frontmatter, body)."""
    return parse_agent_file(path)


# ---------------------------------------------------------------------------
# Active body resolution
# ---------------------------------------------------------------------------

def resolve_active_body(agent_dir: str, agent_id: str, platform: str = '') -> tuple[str, str]:
    """
    Returns (active_body_path, body_content).
    Resolution order:
      1. instructions/<id>.<platform-alias>@latest.md  (platform-specific, e.g. git-mentor.cc@latest.md)
      2. instructions/<id>@latest.md                   (generic latest)
      3. instructions/<id>_latest.md                   (legacy fallback)
      4. <id>.md body                                  (root file, frontmatter stripped)
    """
    instructions_dir = os.path.join(agent_dir, 'instructions')

    # 1. Platform-specific body
    if platform:
        alias = PLATFORM_ALIASES.get(platform, platform)
        platform_file = os.path.join(instructions_dir, f'{agent_id}.{alias}@latest.md')
        if os.path.isfile(platform_file):
            return platform_file, read_file(platform_file)

    # 2. Generic latest
    at_latest = os.path.join(instructions_dir, f'{agent_id}@latest.md')
    if os.path.isfile(at_latest):
        return at_latest, read_file(at_latest)

    # 3. Legacy
    underscore_latest = os.path.join(instructions_dir, f'{agent_id}_latest.md')
    if os.path.isfile(underscore_latest):
        return underscore_latest, read_file(underscore_latest)

    # 4. Root file body
    root_file = os.path.join(agent_dir, f'{agent_id}.md')
    _, body = parse_agent_file(root_file)
    return root_file, body


# ---------------------------------------------------------------------------
# Manifest builder
# ---------------------------------------------------------------------------

def build_manifest(agent_id: str, db_path: str, platform: str,
                   runtime_dir: str = '',
                   github_mode: str = '', github_owner: str = '',
                   github_repo: str = '', github_branch: str = '') -> dict:
    """Build the normalized manifest for one agent."""
    db_path = os.path.expanduser(db_path)
    agent_dir = os.path.join(db_path, agent_id)
    root_file = os.path.join(agent_dir, f'{agent_id}.md')

    # Paths block
    active_body_path, _ = resolve_active_body(agent_dir, agent_id, platform) if os.path.isdir(agent_dir) else (root_file, '')
    runtime_dir_exp = os.path.expanduser(runtime_dir) if runtime_dir else ''

    paths = {
        'agent_dir': agent_dir,
        'root_file': root_file,
        'active_body_file': active_body_path,
        'runtime_file': os.path.join(runtime_dir_exp, f'{agent_id}.md') if runtime_dir_exp else '',
        'import_stage_dir': os.path.join(db_path, '_imports'),
        'github_stage_dir': os.path.join(db_path, '_staging', 'github'),
    }

    # Parse root file
    root_meta = {}
    if os.path.isfile(root_file):
        try:
            fm, _ = parse_agent_file(root_file)
            root_meta = fm
        except yaml.YAMLError:
            pass

    # Deploy block
    deploy = extract_deploy(root_meta, platform)

    # Resolve actual runtime filename — use deploy.name if set, else agent_id
    deploy_name = deploy.get('name', agent_id) if deploy.get('enabled') else agent_id
    runtime_links = _tracked_links_for_agent(
        agent_id=agent_id,
        db_path=db_path,
        platform=platform,
        runtime_dir=runtime_dir_exp,
    )
    if runtime_dir_exp:
        paths['runtime_file'] = _choose_runtime_path(deploy_name, runtime_dir_exp, runtime_links)
        # Also check if there's a file with apm.id matching this agent (canonical lookup)
        _rt_by_id = _find_runtime_by_id(runtime_dir_exp, agent_id)
        if _rt_by_id:
            paths['runtime_file'] = _rt_by_id
    paths['tracked_runtime_files'] = [lnk['path'] for lnk in runtime_links if lnk.get('path')]

    # Runtime metadata
    runtime_meta = None
    runtime_exists = os.path.isfile(paths['runtime_file']) if paths['runtime_file'] else False
    if runtime_exists:
        try:
            rt_fm, _ = parse_agent_file(paths['runtime_file'])
            runtime_meta = rt_fm
        except Exception:
            runtime_meta = None

    # GitHub config
    gh_meta = root_meta.get('github', {}) or {}
    effective_repo = gh_repo = github_repo or gh_meta.get('repo', agent_id)
    effective_branch = github_branch or gh_meta.get('branch', 'main')
    github_info = {
        'mode': github_mode or '',
        'owner': github_owner or '',
        'repo': effective_repo,
        'branch': effective_branch,
        'repo_path': f'{agent_id}/' if github_mode == 'monorepo' else '',
    }
    if not github_mode and not github_owner:
        github_state = 'not-configured'
    else:
        github_state = 'unknown'

    # Compute state
    sync_state = _compute_sync_state(
        agent_id=agent_id,
        agent_dir=agent_dir,
        root_file=root_file,
        deploy=deploy,
        runtime_meta=runtime_meta,
        runtime_exists=runtime_exists,
        runtime_file=paths['runtime_file'],
        db_path=db_path,
        platform=platform,
    )

    eligibility = 'enabled' if deploy.get('enabled') else 'disabled'

    return {
        'id': agent_id,
        'category': _agent_category(root_meta),
        'paths': paths,
        'root_meta': root_meta,
        'deploy': deploy,
        'runtime_meta': runtime_meta,
        'github': github_info,
        'state': {
            'sync': sync_state,
            'github': github_state,
            'eligibility': eligibility,
        },
        'warnings': [],
    }


def _find_runtime_by_id(runtime_dir: str, agent_id: str) -> str:
    """Search runtime dir for a file whose apm.id matches agent_id."""
    if not os.path.isdir(runtime_dir):
        return ''
    for fname in os.listdir(runtime_dir):
        if not fname.endswith('.md'):
            continue
        fpath = os.path.join(runtime_dir, fname)
        try:
            fm, _ = parse_agent_file(fpath)
            apm_block = fm.get('apm', {}) or {}
            if apm_block.get('id') == agent_id:
                return fpath
        except Exception:
            continue
    return ''


def _tracked_links_for_agent(agent_id: str, db_path: str,
                             platform: str = '',
                             runtime_dir: str = '') -> list[dict]:
    """Return live tracked links for an agent, optionally filtered by platform/runtime dir."""
    data = read_links(agent_id, db_path)
    links = data.get('links', [])
    runtime_dir_exp = os.path.expanduser(runtime_dir) if runtime_dir else ''
    filtered = []
    for link in links:
        path = os.path.expanduser(link.get('path', ''))
        if not path:
            continue
        if platform and link.get('platform') not in ('', None, platform):
            continue
        if runtime_dir_exp and os.path.dirname(path) != runtime_dir_exp:
            continue
        entry = dict(link)
        entry['path'] = path
        filtered.append(entry)
    return filtered


def _choose_runtime_path(deploy_name: str, runtime_dir: str,
                         runtime_links: list[dict]) -> str:
    """Choose the primary runtime path for status and diff operations."""
    runtime_dir_exp = os.path.expanduser(runtime_dir) if runtime_dir else ''
    default_path = os.path.join(runtime_dir_exp, f'{deploy_name}.md') if runtime_dir_exp else ''
    if not runtime_links:
        return default_path

    candidates = sorted(lnk.get('path', '') for lnk in runtime_links if lnk.get('path'))
    if default_path and default_path in candidates:
        return default_path
    return candidates[0] if candidates else default_path


def _compute_sync_state(agent_id, agent_dir, root_file, deploy,
                         runtime_meta, runtime_exists, runtime_file,
                         db_path, platform) -> str:
    """Compute the library/runtime sync state dimension."""
    library_exists = os.path.isdir(agent_dir) and os.path.isfile(root_file)

    if not library_exists:
        if runtime_meta and runtime_meta.get('apm', {}).get('id') == agent_id:
            return 'orphan'
        return 'orphan'

    if not deploy.get('enabled'):
        return 'no-deploy'

    if not runtime_exists:
        return 'ready'

    # Symlink mode: runtime is a symlink — compare link target to expected split file
    if os.path.islink(runtime_file):
        active_body_path, _ = resolve_active_body(agent_dir, agent_id, platform)
        try:
            link_target = os.path.realpath(runtime_file)
            expected = os.path.realpath(active_body_path)
            if link_target == expected:
                return 'linked'
            apm_id = ((runtime_meta or {}).get('apm', {}) or {}).get('id')
            if apm_id != agent_id:
                return 'outdated'
        except Exception:
            return 'outdated'

    # Runtime exists — check if managed
    if runtime_meta is None:
        return 'unmanaged'

    apm_block = runtime_meta.get('apm', {}) or {}
    if not apm_block.get('id'):
        return 'unmanaged'

    if apm_block.get('id') != agent_id:
        return 'orphan'

    # Managed runtime — compare content against actual runtime file
    try:
        _, active_body = resolve_active_body(agent_dir, agent_id, platform)
        rt_fm, rt_body_text = parse_agent_file(runtime_file)

        lib_body_norm = normalize_body(active_body)
        rt_body_norm = normalize_body(rt_body_text)

        lib_deploy = deploy
        rt_name = rt_fm.get('name', '')
        rt_desc = rt_fm.get('description', '')
        rt_model = rt_fm.get('model', '')
        rt_tools = normalize_tools(rt_fm.get('tools'))

        if (lib_body_norm != rt_body_norm or
            lib_deploy.get('name', '') != rt_name or
            lib_deploy.get('description', '') != rt_desc or
            lib_deploy.get('model', '') != rt_model or
            lib_deploy.get('tools', []) != rt_tools):
            return 'outdated'
        return 'installed'
    except Exception:
        return 'outdated'


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_agent(agent_id: str, db_path: str) -> dict:
    """Validate one agent. Returns {valid, errors, warnings}."""
    errors = []
    warnings = []
    db_path = os.path.expanduser(db_path)

    # ID format
    if not CANONICAL_ID_RE.match(agent_id):
        errors.append(f"Invalid canonical ID format: '{agent_id}'. Must match ^[a-z0-9][a-z0-9-]*$")

    agent_dir = os.path.join(db_path, agent_id)
    root_file = os.path.join(agent_dir, f'{agent_id}.md')

    # Root file must exist
    if not os.path.isdir(agent_dir):
        errors.append(f"Agent directory missing: {agent_dir}")
        return {'valid': False, 'id': agent_id, 'errors': errors, 'warnings': warnings}

    if not os.path.isfile(root_file):
        errors.append(f"Root file missing: {root_file}")
        return {'valid': False, 'id': agent_id, 'errors': errors, 'warnings': warnings}

    # Parse frontmatter
    try:
        fm, body = parse_agent_file(root_file)
    except yaml.YAMLError as e:
        errors.append(f"YAML parse error in {root_file}: {e}")
        return {'valid': False, 'id': agent_id, 'errors': errors, 'warnings': warnings}
    except Exception as e:
        errors.append(f"Error reading {root_file}: {e}")
        return {'valid': False, 'id': agent_id, 'errors': errors, 'warnings': warnings}

    # Check deploy block if present
    deploy_block = fm.get('deploy', {}) or {}
    for plat, plat_config in deploy_block.items():
        if not isinstance(plat_config, dict):
            warnings.append(f"deploy.{plat} is not a mapping")
            continue
        if plat_config.get('enabled', True) is False:
            continue
        if not plat_config.get('name'):
            errors.append(f"deploy.{plat}.name is required")
        if not plat_config.get('description'):
            errors.append(f"deploy.{plat}.description is required")
        tools = plat_config.get('tools')
        if tools is not None and not isinstance(tools, (list, str)):
            errors.append(f"deploy.{plat}.tools must be a list")

    return {
        'valid': len(errors) == 0,
        'id': agent_id,
        'errors': errors,
        'warnings': warnings,
    }


def validate_all(db_path: str) -> dict:
    """Validate all agents in db. Also detect deploy alias collisions."""
    db_path = os.path.expanduser(db_path)
    agent_ids = scan_library(db_path)

    results = []
    all_valid = True
    deploy_names = {}  # platform -> {name -> [agent_ids]}
    collisions = []

    for aid in agent_ids:
        result = validate_agent(aid, db_path)
        results.append(result)
        if not result['valid']:
            all_valid = False

        # Collect deploy aliases for collision detection
        root_file = os.path.join(db_path, aid, f'{aid}.md')
        if os.path.isfile(root_file):
            try:
                fm, _ = parse_agent_file(root_file)
                deploy_block = fm.get('deploy', {}) or {}
                for plat, plat_cfg in deploy_block.items():
                    if not isinstance(plat_cfg, dict):
                        continue
                    if plat_cfg.get('enabled', True) is False:
                        continue
                    alias = plat_cfg.get('name', '')
                    if alias:
                        key = f'{plat}:{alias}'
                        deploy_names.setdefault(key, []).append(aid)
            except Exception:
                pass

    for key, aids in deploy_names.items():
        if len(aids) > 1:
            plat, alias = key.split(':', 1)
            collisions.append({
                'type': 'alias',
                'platform': plat,
                'alias': alias,
                'agents': aids,
            })
            all_valid = False

    return {
        'valid': all_valid,
        'agents': results,
        'collisions': collisions,
        'warnings': [],
    }


# ---------------------------------------------------------------------------
# Diff computation
# ---------------------------------------------------------------------------

def diff_manifest(agent_id: str, db_path: str, platform: str, runtime_dir: str) -> dict:
    """Compare library agent vs installed runtime."""
    db_path = os.path.expanduser(db_path)
    runtime_dir = os.path.expanduser(runtime_dir) if runtime_dir else ''

    agent_dir = os.path.join(db_path, agent_id)
    root_file = os.path.join(agent_dir, f'{agent_id}.md')

    if not os.path.isfile(root_file):
        return {
            'id': agent_id,
            'platform': platform,
            'in_sync': False,
            'runtime_exists': False,
            'changed_fields': [],
            'details': {},
            'error': f'Root file not found: {root_file}',
        }

    # Library values
    try:
        fm, _ = parse_agent_file(root_file)
    except yaml.YAMLError as e:
        return {'id': agent_id, 'platform': platform, 'in_sync': False,
                'runtime_exists': False, 'changed_fields': [], 'details': {},
                'error': f'YAML error: {e}'}

    deploy = extract_deploy(fm, platform)
    _, lib_body = resolve_active_body(agent_dir, agent_id, platform)
    lib_body_norm = normalize_body(lib_body)

    # Find runtime file
    deploy_name = deploy.get('name', agent_id) if deploy.get('enabled') else agent_id
    runtime_file = ''
    if runtime_dir:
        # Check for file with matching apm.id first
        runtime_file = _find_runtime_by_id(runtime_dir, agent_id)
        if not runtime_file:
            runtime_file = os.path.join(runtime_dir, f'{deploy_name}.md')

    runtime_exists = bool(runtime_file) and os.path.isfile(runtime_file)

    if not runtime_exists:
        return {
            'id': agent_id,
            'platform': platform,
            'in_sync': False,
            'runtime_exists': False,
            'changed_fields': [],
            'details': {},
        }

    # Runtime values
    try:
        rt_fm, rt_body = parse_agent_file(runtime_file)
    except Exception as e:
        return {'id': agent_id, 'platform': platform, 'in_sync': False,
                'runtime_exists': True, 'changed_fields': [], 'details': {},
                'error': f'Error reading runtime file: {e}'}

    rt_body_norm = normalize_body(rt_body)

    changed = []
    details = {}

    def check_field(field, lib_val, rt_val):
        if lib_val != rt_val:
            changed.append(field)
            details[field] = {'library': lib_val, 'runtime': rt_val}

    check_field('name', deploy.get('name', ''), rt_fm.get('name', ''))
    check_field('description', deploy.get('description', ''), rt_fm.get('description', ''))
    check_field('model', deploy.get('model', ''), rt_fm.get('model', ''))
    check_field('tools', deploy.get('tools', []), normalize_tools(rt_fm.get('tools')))

    # Body diff
    if lib_body_norm != rt_body_norm:
        changed.append('body')
        lib_lines = lib_body_norm.split('\n')
        rt_lines = rt_body_norm.split('\n')
        details['body'] = {
            'library_lines': len(lib_lines),
            'runtime_lines': len(rt_lines),
        }

    return {
        'id': agent_id,
        'platform': platform,
        'in_sync': len(changed) == 0,
        'runtime_exists': True,
        'changed_fields': changed,
        'details': details,
    }


# ---------------------------------------------------------------------------
# List and status
# ---------------------------------------------------------------------------

def _agent_category(fm: dict) -> str:
    """Return the category/group for an agent from its frontmatter (empty string if none)."""
    return str(fm.get('category') or fm.get('group') or '').strip()


def list_agents(db_path: str) -> dict:
    """List all agent IDs in the library."""
    db_path = os.path.expanduser(db_path)
    ids = scan_library(db_path)
    agents = []
    for aid in ids:
        root_file = os.path.join(db_path, aid, f'{aid}.md')
        name = aid
        category = ''
        try:
            fm, _ = parse_agent_file(root_file)
            name = fm.get('name', aid)
            category = _agent_category(fm)
        except Exception:
            pass
        agents.append({'id': aid, 'name': name, 'category': category})
    return {'agents': agents}


def list_categories(db_path: str) -> dict:
    """
    Return a map of category -> [agent_ids] for all agents in the library.
    Agents with no category/group are listed under '' (empty string key).
    """
    db_path = os.path.expanduser(db_path)
    ids = scan_library(db_path)
    categories: dict[str, list] = {}
    for aid in ids:
        root_file = os.path.join(db_path, aid, f'{aid}.md')
        category = ''
        try:
            fm, _ = parse_agent_file(root_file)
            category = _agent_category(fm)
        except Exception:
            pass
        categories.setdefault(category, []).append(aid)
    # Sort IDs within each category
    for cat in categories:
        categories[cat].sort()
    return {'categories': categories}


def status_agents(db_path: str, platform: str, runtime_dir: str) -> dict:
    """List agents with full state for each."""
    db_path = os.path.expanduser(db_path)
    ids = scan_library(db_path)

    agents = []
    # Also scan runtime for untracked/orphan files
    rt_dir = os.path.expanduser(runtime_dir) if runtime_dir else ''
    rt_files = {}
    if rt_dir and os.path.isdir(rt_dir):
        for fname in os.listdir(rt_dir):
            if fname.endswith('.md'):
                fpath = os.path.join(rt_dir, fname)
                try:
                    fm, _ = parse_agent_file(fpath)
                    apm_block = fm.get('apm', {}) or {}
                    rt_id = apm_block.get('id', '')
                    rt_files[fname] = {'path': fpath, 'fm': fm, 'apm_id': rt_id}
                except Exception:
                    rt_files[fname] = {'path': fpath, 'fm': {}, 'apm_id': ''}

    accounted_rt = set()

    for aid in ids:
        manifest = build_manifest(
            agent_id=aid,
            db_path=db_path,
            platform=platform,
            runtime_dir=runtime_dir,
        )
        agents.append(manifest)
        # Track which runtime files are accounted for
        rt_file = manifest['paths'].get('runtime_file', '')
        if rt_file:
            accounted_rt.add(rt_file)
        for tracked in manifest['paths'].get('tracked_runtime_files', []):
            if tracked:
                accounted_rt.add(tracked)

    # Add untracked runtime files as entries
    for fname, info in rt_files.items():
        fpath = info['path']
        if fpath in accounted_rt:
            continue
        apm_id = info['apm_id']
        if apm_id and apm_id not in ids:
            # Orphan: apm.id present but not in library
            agents.append({
                'id': apm_id,
                'paths': {'runtime_file': fpath},
                'root_meta': {},
                'deploy': {'platform': platform, 'enabled': False},
                'runtime_meta': info['fm'],
                'github': {},
                'state': {'sync': 'orphan', 'github': 'not-configured', 'eligibility': 'disabled'},
                'warnings': [f'Runtime file {fname} references unknown canonical id {apm_id}'],
            })
        elif not apm_id:
            # Untracked
            name_from_file = os.path.splitext(fname)[0]
            agents.append({
                'id': name_from_file,
                'paths': {'runtime_file': fpath},
                'root_meta': {},
                'deploy': {'platform': platform, 'enabled': False},
                'runtime_meta': info['fm'],
                'github': {},
                'state': {'sync': 'unmanaged', 'github': 'not-configured', 'eligibility': 'disabled'},
                'warnings': [f'Runtime file {fname} has no apm.id — not managed by apm'],
            })

    return {'agents': agents, 'platform': platform}


def list_skills(db_path: str) -> dict:
    """List all skill IDs in the library."""
    db_path = os.path.expanduser(db_path)
    records = _scan_skill_records(db_path)
    skills = []
    for rec in records:
        sid = rec['id']
        skill_file = rec['skill_file']
        name = sid
        description = ''
        try:
            fm, _ = parse_skill_file(skill_file)
            name = fm.get('name', sid)
            description = fm.get('description', '')
        except Exception:
            pass
        skills.append({
            'id': sid,
            'name': name,
            'description': description,
            'source': {
                'kind': rec.get('source', ''),
                'repo': rec.get('repo', ''),
            },
        })
    return {'skills': skills}


def _collect_dir_files(base: str) -> dict:
    """Return {relative_path: content} for all files under base."""
    result = {}
    if not os.path.isdir(base):
        return result
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in ('versions', '.git')]
        for fname in files:
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, base)
            try:
                with open(full) as f:
                    result[rel] = f.read()
            except Exception:
                result[rel] = None
    return result


def status_skills(db_path: str, platform: str = '', runtime_dir: str = '') -> dict:
    """List skills with full state for each."""
    db_path = os.path.expanduser(db_path)
    records = _scan_skill_records(db_path)
    skills = []
    runtime_dir_exp = os.path.expanduser(runtime_dir) if runtime_dir else ''
    skill_platform_supported = (not platform) or (platform in SKILL_SUPPORTED_PLATFORMS)

    for rec in records:
        sid = rec['id']
        skill_dir = rec['skill_dir']
        skill_file = rec['skill_file']
        root_meta = {}
        try:
            root_meta, _ = parse_skill_file(skill_file)
        except Exception:
            pass

        runtime_path = os.path.join(runtime_dir_exp, sid) if runtime_dir_exp else ''
        state = 'ready'
        warnings = []
        if not os.path.isfile(skill_file):
            state = 'invalid'
            warnings.append(f'Missing SKILL.md in {skill_dir}')
        elif platform and not skill_platform_supported:
            state = 'no-deploy'
            warnings.append(f"Platform '{platform}' does not support skill installs")
        elif runtime_path:
            if os.path.islink(runtime_path):
                if os.path.realpath(runtime_path) == os.path.realpath(skill_dir):
                    state = 'linked'
                else:
                    state = 'outdated'
                    warnings.append(f'Runtime link target differs from canonical skill dir: {runtime_path}')
            elif os.path.lexists(runtime_path):
                state = 'outdated'
                warnings.append(f'Runtime path exists but is not a managed symlink: {runtime_path}')

        skills.append({
            'id': sid,
            'paths': {
                'skill_dir': skill_dir,
                'root_file': skill_file,
                'runtime_file': runtime_path,
                'github_stage_dir': os.path.join(db_path, '_staging', 'github'),
            },
            'root_meta': root_meta,
            'source': {
                'kind': rec.get('source', ''),
                'repo': rec.get('repo', ''),
            },
            'deploy': {'enabled': state != 'no-deploy', 'platform': platform},
            'runtime_meta': None,
            'github': {},
            'state': {
                'sync': state,
                'github': 'not-configured',
                'eligibility': 'enabled' if state != 'no-deploy' else 'disabled',
            },
            'warnings': warnings,
        })

    return {'agents': skills, 'skills': skills, 'mode': 'skills', 'platform': platform}


# ---------------------------------------------------------------------------
# Runtime content generation
# ---------------------------------------------------------------------------

def generate_runtime_content(agent_id: str, db_path: str, platform: str) -> dict:
    """
    Generate the full content string for a runtime file.
    Returns {"content": "<file text>", "runtime_file": "...", ...}

    Runtime file contract (SPEC_RUNTIME.md):
      ---
      name: <deploy.name>
      description: <deploy.description>
      model: <deploy.model>
      tools: [normalized list]
      apm:
        id: <canonical-id>
        platform: <platform>
        installed-from: <absolute library path>
        installed-at: <UTC ISO timestamp>
      ---
      <active body>
    """
    db_path = os.path.expanduser(db_path)
    agent_dir = os.path.join(db_path, agent_id)
    root_file = os.path.join(agent_dir, f'{agent_id}.md')

    if not os.path.isfile(root_file):
        return {'error': f'Root file not found: {root_file}', 'exit_code': 2}

    try:
        fm, _ = parse_agent_file(root_file)
    except yaml.YAMLError as e:
        return {'error': f'YAML parse error: {e}', 'exit_code': 1}

    deploy = extract_deploy(fm, platform)
    if not deploy.get('enabled'):
        return {
            'error': f"Agent '{agent_id}' has no enabled deploy config for platform '{platform}'",
            'exit_code': 1,
        }

    # Resolve active body
    active_body_path, active_body = resolve_active_body(agent_dir, agent_id, platform)

    # Build frontmatter dict (ordered for readable output)
    installed_at = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    rt_fm: dict = {}
    rt_fm['name'] = deploy.get('name', agent_id)
    if deploy.get('description'):
        rt_fm['description'] = deploy['description']

    # Platform-aware frontmatter fields
    if platform == 'cursor':
        # Cursor subagents: model (default inherit), readonly, is_background
        rt_fm['model'] = deploy.get('model') or 'inherit'
        if deploy.get('readonly') is not None:
            rt_fm['readonly'] = deploy['readonly']
        if deploy.get('is_background') is not None:
            rt_fm['is_background'] = deploy['is_background']
    elif platform == 'agents-dir':
        # Generic cross-tool: model defaults to inherit, applyTo, tags
        model = deploy.get('model')
        rt_fm['model'] = model if model else 'inherit'
        apply_to = deploy.get('applyTo', [])
        if apply_to:
            rt_fm['applyTo'] = apply_to
        tags = deploy.get('tags', [])
        if tags:
            rt_fm['tags'] = tags
    else:
        # Claude Code and others: model optional, tools, applyTo, tags
        if deploy.get('model'):
            rt_fm['model'] = deploy['model']
        tools = deploy.get('tools', [])
        if tools:
            rt_fm['tools'] = tools
        apply_to = deploy.get('applyTo', [])
        if apply_to:
            rt_fm['applyTo'] = apply_to
        tags = deploy.get('tags', [])
        if tags:
            rt_fm['tags'] = tags
    rt_fm['apm'] = {
        'id': agent_id,
        'platform': platform,
        'installed-from': agent_dir,
        'installed-at': installed_at,
    }

    # Serialize to YAML
    fm_yaml = yaml.dump(rt_fm, default_flow_style=False, allow_unicode=True, sort_keys=False)
    # Build file content
    body_text = active_body.strip('\n')
    content = f'---\n{fm_yaml}---\n\n{body_text}\n'

    return {
        'content': content,
        'agent_id': agent_id,
        'platform': platform,
        'active_body_file': active_body_path,
        'installed_at': installed_at,
    }


# ---------------------------------------------------------------------------
# Import subsystem
# ---------------------------------------------------------------------------

def analyze_import(runtime_file: str, db_path: str, platform: str) -> dict:
    """
    Analyze a runtime file and determine the best import mode.

    Returns a dict with:
      - runtime_file: absolute path
      - candidate_id: best-guess canonical ID
      - match_type: 'apm_id' | 'filename_id' | 'filename_alias' | 'body_hash' | 'new'
      - mode: 'import-new' | 'import-merge' | 'link-existing'
      - library_exists: bool — whether candidate_id already has a library entry
      - diff: dict from diff_manifest if library exists, else None
      - runtime_fm: frontmatter dict from runtime file
      - runtime_body: body text
      - warnings: list of strings
    """
    db_path = os.path.expanduser(db_path)
    runtime_file = os.path.expanduser(runtime_file)

    warnings = []

    # Parse runtime file
    try:
        rt_fm, rt_body = parse_agent_file(runtime_file)
    except yaml.YAMLError as e:
        return {'error': f'YAML parse error in runtime file: {e}', 'exit_code': 1}
    except Exception as e:
        return {'error': f'Cannot read runtime file: {e}', 'exit_code': 2}

    fname = os.path.basename(runtime_file)
    fname_stem = os.path.splitext(fname)[0]  # strip .md

    # Match heuristics (SPEC_IMPORT.md — conservative order)
    apm_block = rt_fm.get('apm', {}) or {}
    existing_apm_id = apm_block.get('id', '')
    all_library_ids = scan_library(db_path)

    candidate_id = ''
    match_type = 'new'

    # 1. Existing apm.id
    if existing_apm_id and existing_apm_id in all_library_ids:
        candidate_id = existing_apm_id
        match_type = 'apm_id'

    # 2. Filename equals canonical ID
    if not candidate_id and fname_stem in all_library_ids:
        candidate_id = fname_stem
        match_type = 'filename_id'

    # 3. Filename equals a deploy alias for some library agent
    if not candidate_id:
        for aid in all_library_ids:
            root_file = os.path.join(db_path, aid, f'{aid}.md')
            if not os.path.isfile(root_file):
                continue
            try:
                lib_fm, _ = parse_agent_file(root_file)
                deploy_block = lib_fm.get('deploy', {}) or {}
                plat_cfg = deploy_block.get(platform, {}) or {}
                if plat_cfg.get('name') == fname_stem:
                    candidate_id = aid
                    match_type = 'filename_alias'
                    break
            except Exception:
                continue

    # 4. Body hash match
    if not candidate_id:
        rt_hash = body_hash(rt_body)
        for aid in all_library_ids:
            agent_dir = os.path.join(db_path, aid)
            try:
                _, lib_body = resolve_active_body(agent_dir, aid)
                if body_hash(lib_body) == rt_hash:
                    candidate_id = aid
                    match_type = 'body_hash'
                    break
            except Exception:
                continue

    # If still no match, use filename stem as new candidate ID
    if not candidate_id:
        candidate_id = fname_stem
        match_type = 'new'
        # Sanitize: lowercase, replace spaces/underscores with hyphens
        candidate_id = re.sub(r'[^a-z0-9-]', '-', candidate_id.lower()).strip('-')
        if not CANONICAL_ID_RE.match(candidate_id):
            candidate_id = 'imported-agent'
            warnings.append(f'Could not derive valid canonical ID from filename "{fname_stem}"; using "imported-agent"')

    library_exists = os.path.isdir(os.path.join(db_path, candidate_id)) and \
                     os.path.isfile(os.path.join(db_path, candidate_id, f'{candidate_id}.md'))

    # Determine mode
    if not library_exists:
        mode = 'import-new'
    elif match_type == 'apm_id':
        mode = 'link-existing'
    else:
        mode = 'import-merge'

    # Compute diff if library entry exists
    diff_result = None
    if library_exists:
        diff_result = diff_manifest(
            agent_id=candidate_id,
            db_path=db_path,
            platform=platform,
            runtime_dir=os.path.dirname(runtime_file),
        )

    return {
        'runtime_file': runtime_file,
        'candidate_id': candidate_id,
        'match_type': match_type,
        'mode': mode,
        'library_exists': library_exists,
        'diff': diff_result,
        'runtime_fm': rt_fm,
        'runtime_body': rt_body,
        'warnings': warnings,
    }


def build_import_draft(runtime_file: str, candidate_id: str, db_path: str,
                        platform: str, timestamp: str) -> dict:
    """
    Build the content for a staged import draft under _imports/<candidate_id>-<timestamp>/.

    Returns:
      - stage_dir: path where draft should be written
      - root_file_content: content for <candidate_id>.md (frontmatter + pointer comment)
      - latest_file_content: content for instructions/<candidate_id>@latest.md
      - root_file_path: full path
      - latest_file_path: full path
    """
    db_path = os.path.expanduser(db_path)
    runtime_file = os.path.expanduser(runtime_file)

    try:
        rt_fm, rt_body = parse_agent_file(runtime_file)
    except Exception as e:
        return {'error': str(e), 'exit_code': 2}

    stage_dir = os.path.join(db_path, '_imports', f'{candidate_id}-{timestamp}')

    # Derive deploy block from runtime frontmatter (AGENT_ENTRY_SCHEMA.md §5)
    deploy_cfg: dict = {}
    name = rt_fm.get('name', candidate_id)
    description = rt_fm.get('description', '')
    model = rt_fm.get('model', '')
    tools = normalize_tools(rt_fm.get('tools'))

    if name or description or model or tools:
        deploy_cfg = {platform: {}}
        if name:
            deploy_cfg[platform]['name'] = name
        if description:
            deploy_cfg[platform]['description'] = description
        if model:
            deploy_cfg[platform]['model'] = model
        if tools:
            deploy_cfg[platform]['tools'] = tools

    # Build root frontmatter (AGENT_ENTRY_SCHEMA.md import defaults)
    import_date = timestamp[:10]  # YYYY-MM-DD
    root_fm: dict = {}
    root_fm['id'] = candidate_id
    root_fm['name'] = name or candidate_id
    if description:
        root_fm['description'] = description
    root_fm['status'] = 'progress'
    root_fm['ver-stat'] = 'Imported'
    root_fm['ver-num'] = 1
    root_fm['platform'] = platform
    root_fm['origin'] = 'claude-import'
    root_fm['updated'] = import_date
    if deploy_cfg:
        root_fm['deploy'] = deploy_cfg

    # Preserve any extra fields from runtime fm that aren't apm-managed
    apm_managed = {'name', 'description', 'model', 'tools', 'apm'}
    for k, v in rt_fm.items():
        if k not in apm_managed and k not in root_fm:
            root_fm[k] = v

    root_fm_yaml = yaml.dump(root_fm, default_flow_style=False, allow_unicode=True, sort_keys=False)
    root_file_content = f'---\n{root_fm_yaml}---\n\n<!-- See instructions/{candidate_id}@latest.md for active body -->\n'
    latest_file_content = rt_body.strip('\n') + '\n'

    return {
        'stage_dir': stage_dir,
        'root_file_path': os.path.join(stage_dir, f'{candidate_id}.md'),
        'root_file_content': root_file_content,
        'latest_file_path': os.path.join(stage_dir, 'instructions', f'{candidate_id}@latest.md'),
        'latest_file_content': latest_file_content,
        'candidate_id': candidate_id,
        'platform': platform,
    }


def scan_unmanaged_runtime(runtime_dir: str, db_path: str,
                            ignore_file: str = '') -> dict:
    """
    Scan runtime_dir for files not linked to the library.
    Returns lists of: unmanaged, managed, orphan, ignored.
    ignore_file: path to ignored-runtime.txt
    """
    runtime_dir = os.path.expanduser(runtime_dir)
    db_path = os.path.expanduser(db_path)

    # Load ignore list
    ignored_paths: set = set()
    if ignore_file and os.path.isfile(ignore_file):
        with open(ignore_file) as f:
            for line in f:
                line = line.strip()
                if line and ':' in line:
                    _, path = line.split(':', 1)
                    ignored_paths.add(path.strip())

    all_library_ids = set(scan_library(db_path))

    unmanaged = []
    managed = []
    orphan = []
    ignored = []

    if not os.path.isdir(runtime_dir):
        return {
            'runtime_dir': runtime_dir,
            'unmanaged': [], 'managed': [], 'orphan': [], 'ignored': [],
            'warning': f'Runtime directory not found: {runtime_dir}',
        }

    for fname in sorted(os.listdir(runtime_dir)):
        if not fname.endswith('.md'):
            continue
        fpath = os.path.join(runtime_dir, fname)

        if fpath in ignored_paths:
            ignored.append({'file': fpath, 'name': fname})
            continue

        try:
            fm, body = parse_agent_file(fpath)
        except Exception:
            unmanaged.append({'file': fpath, 'name': fname, 'apm_id': '', 'error': 'parse error'})
            continue

        apm_block = fm.get('apm', {}) or {}
        apm_id = apm_block.get('id', '')

        if apm_id:
            if apm_id in all_library_ids:
                managed.append({'file': fpath, 'name': fname, 'apm_id': apm_id})
            else:
                orphan.append({'file': fpath, 'name': fname, 'apm_id': apm_id})
        else:
            unmanaged.append({'file': fpath, 'name': fname, 'apm_id': ''})

    return {
        'runtime_dir': runtime_dir,
        'unmanaged': unmanaged,
        'managed': managed,
        'orphan': orphan,
        'ignored': ignored,
    }


# ---------------------------------------------------------------------------
# GitHub diff helper
# ---------------------------------------------------------------------------

def github_diff_agent(agent_id: str, db_path: str, github_dir: str,
                      entity: str = 'agents') -> dict:
    """
    Compare canonical library agent dir against github_dir (a clone subtree).
    github_dir: path to the agent folder inside the cloned repo
                (e.g. /tmp/clone/git-mentor/ for monorepo).

    Returns a diff object:
      {
        "agent_id": ...,
        "library_dir": ...,
        "github_dir": ...,
        "in_sync": bool,
        "missing_in_github": [filenames],
        "missing_in_library": [filenames],
        "changed_files": [filenames],
        "details": { filename: { "library": str|None, "github": str|None } }
      }
    """
    db_path = os.path.expanduser(db_path)
    if entity == 'agents':
        entity_dir = os.path.join(db_path, agent_id)
    else:
        entity_dir = _skill_record_map(db_path).get(agent_id, {}).get('skill_dir', os.path.join(db_path, agent_id))
    lib_files = _collect_dir_files(entity_dir)
    gh_files = _collect_dir_files(github_dir)

    all_keys = set(lib_files) | set(gh_files)
    missing_in_github = []
    missing_in_library = []
    changed_files = []
    details = {}

    for key in sorted(all_keys):
        lib_content = lib_files.get(key)
        gh_content = gh_files.get(key)

        if key not in gh_files:
            missing_in_github.append(key)
            details[key] = {'library': lib_content, 'github': None}
        elif key not in lib_files:
            missing_in_library.append(key)
            details[key] = {'library': None, 'github': gh_content}
        elif lib_content != gh_content:
            changed_files.append(key)
            details[key] = {'library': lib_content, 'github': gh_content}

    in_sync = not (missing_in_github or missing_in_library or changed_files)

    return {
        'agent_id': agent_id,
        'library_dir': entity_dir,
        'github_dir': github_dir,
        'entity': entity,
        'in_sync': in_sync,
        'missing_in_github': missing_in_github,
        'missing_in_library': missing_in_library,
        'changed_files': changed_files,
        'details': details,
    }


def github_status_agents(db_path: str, github_clone_dir: str,
                          github_mode: str, entity: str = 'agents') -> dict:
    """
    For each agent in the library, compute its GitHub sync state.
    github_clone_dir: root of the cloned monorepo.
    Returns per-agent status list.
    """
    db_path = os.path.expanduser(db_path)
    agent_ids = scan_library(db_path) if entity == 'agents' else scan_skills(db_path)
    agents = []

    for agent_id in sorted(agent_ids):
        if github_mode == 'monorepo':
            gh_agent_dir = os.path.join(github_clone_dir, agent_id)
        else:
            gh_agent_dir = github_clone_dir  # per-agent: clone root IS the agent dir

        if not os.path.isdir(github_clone_dir):
            state = 'not-cloned'
            diff = {}
        elif not os.path.isdir(gh_agent_dir):
            state = 'not-pushed'
            diff = {}
        else:
            diff = github_diff_agent(agent_id, db_path, gh_agent_dir, entity=entity)
            state = 'in-sync' if diff['in_sync'] else 'outdated'

        agents.append({
            'id': agent_id,
            'github_state': state,
            'diff': diff,
        })

    key = 'agents' if entity == 'agents' else 'skills'
    return {'agents': agents, key: agents, 'github_mode': github_mode, 'entity': entity}


# ---------------------------------------------------------------------------
# CLI dispatch
# ---------------------------------------------------------------------------

def cmd_parse_root(args):
    path = args.file
    try:
        fm, body = parse_agent_file(path)
        print(_dump({
            'file': path,
            'frontmatter': fm,
            'body_length': len(body),
            'body_preview': body[:200] if body else '',
        }))
    except yaml.YAMLError as e:
        print(_dump({'error': f'YAML parse error: {e}', 'file': path, 'exit_code': 1}))
        sys.exit(1)
    except FileNotFoundError:
        print(_dump({'error': f'File not found: {path}', 'exit_code': 2}))
        sys.exit(2)
    except Exception as e:
        print(_dump({'error': str(e), 'file': path, 'exit_code': 2}))
        sys.exit(2)


def cmd_parse_runtime(args):
    path = args.file
    try:
        fm, body = parse_agent_file(path)
        apm_block = fm.get('apm', {}) or {}
        print(_dump({
            'file': path,
            'frontmatter': fm,
            'apm_id': apm_block.get('id', ''),
            'managed': bool(apm_block.get('id')),
            'body_length': len(body),
        }))
    except yaml.YAMLError as e:
        print(_dump({'error': f'YAML parse error: {e}', 'file': path, 'exit_code': 1}))
        sys.exit(1)
    except Exception as e:
        print(_dump({'error': str(e), 'file': path, 'exit_code': 2}))
        sys.exit(2)


def cmd_build_manifest(args):
    manifest = build_manifest(
        agent_id=args.id,
        db_path=args.db,
        platform=args.platform,
        runtime_dir=getattr(args, 'runtime_dir', '') or '',
        github_mode=getattr(args, 'github_mode', '') or '',
        github_owner=getattr(args, 'github_owner', '') or '',
        github_repo=getattr(args, 'github_repo', '') or '',
        github_branch=getattr(args, 'github_branch', '') or '',
    )
    print(_dump(manifest))


def cmd_validate_agent(args):
    result = validate_agent(args.id, args.db)
    print(_dump(result))
    if not result['valid']:
        sys.exit(1)


def cmd_validate_all(args):
    result = validate_all(args.db)
    print(_dump(result))
    if not result['valid']:
        sys.exit(1)


def cmd_diff_manifest(args):
    result = diff_manifest(
        agent_id=args.id,
        db_path=args.db,
        platform=args.platform,
        runtime_dir=getattr(args, 'runtime_dir', '') or '',
    )
    print(_dump(result))
    if not result.get('in_sync', True):
        sys.exit(1)


def cmd_analyze_import(args):
    result = analyze_import(
        runtime_file=args.file,
        db_path=args.db,
        platform=args.platform,
    )
    if 'error' in result:
        print(_dump(result))
        sys.exit(result.get('exit_code', 2))
    print(_dump(result))


def cmd_build_import_draft(args):
    result = build_import_draft(
        runtime_file=args.file,
        candidate_id=args.id,
        db_path=args.db,
        platform=args.platform,
        timestamp=args.timestamp,
    )
    if 'error' in result:
        print(_dump(result))
        sys.exit(result.get('exit_code', 2))
    print(_dump(result))


def cmd_scan_unmanaged(args):
    result = scan_unmanaged_runtime(
        runtime_dir=args.runtime_dir,
        db_path=args.db,
        ignore_file=getattr(args, 'ignore_file', '') or '',
    )
    print(_dump(result))


def generate_split_file(agent_id: str, db_path: str, platform: str) -> dict:
    """
    Auto-generate a platform-specific split file from the root body.
    Creates instructions/<id>.<platform-alias>@latest.md if it doesn't exist.
    Returns {path, created, already_existed}.
    """
    db_path = os.path.expanduser(db_path)
    agent_dir = os.path.join(db_path, agent_id)
    root_file = os.path.join(agent_dir, f'{agent_id}.md')

    if not os.path.isfile(root_file):
        return {'error': f'Root file not found: {root_file}', 'exit_code': 2}

    alias = PLATFORM_ALIASES.get(platform, platform)
    instructions_dir = os.path.join(agent_dir, 'instructions')
    split_file = os.path.join(instructions_dir, f'{agent_id}.{alias}@latest.md')

    if os.path.isfile(split_file):
        return {'path': split_file, 'created': False, 'already_existed': True}

    # Read root body (frontmatter stripped)
    try:
        _, body = parse_agent_file(root_file)
    except Exception as e:
        return {'error': f'Failed to read root file: {e}', 'exit_code': 2}

    os.makedirs(instructions_dir, exist_ok=True)
    try:
        with open(split_file, 'w', encoding='utf-8') as f:
            f.write(body)
    except Exception as e:
        return {'error': f'Failed to write split file: {e}', 'exit_code': 2}

    return {'path': split_file, 'created': True, 'already_existed': False}


def read_links(agent_id: str, db_path: str) -> dict:
    """Read links.json for an agent. Returns {links: [...]}."""
    db_path = os.path.expanduser(db_path)
    links_file = os.path.join(db_path, agent_id, 'links.json')
    if not os.path.isfile(links_file):
        return {'links': []}
    try:
        with open(links_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        # Prune stale entries (link path no longer exists)
        links = [lnk for lnk in data.get('links', [])
                 if os.path.islink(os.path.expanduser(lnk.get('path', '')))]
        return {'links': links}
    except Exception as e:
        return {'error': str(e), 'links': []}


def write_links(agent_id: str, db_path: str, links: list) -> dict:
    """Write links list to links.json. Prunes stale entries first."""
    db_path = os.path.expanduser(db_path)
    agent_dir = os.path.join(db_path, agent_id)
    links_file = os.path.join(agent_dir, 'links.json')

    # Prune stale (path no longer a symlink)
    live = [lnk for lnk in links
            if os.path.islink(os.path.expanduser(lnk.get('path', '')))]

    try:
        os.makedirs(agent_dir, exist_ok=True)
        with open(links_file, 'w', encoding='utf-8') as f:
            json.dump({'links': live}, f, indent=2)
        return {'ok': True, 'links': live}
    except Exception as e:
        return {'error': str(e)}


def list_all_links(db_path: str) -> dict:
    """List all agents that have active links. Returns {agents: [{id, links}]}."""
    db_path = os.path.expanduser(db_path)
    result = []
    for agent_id in scan_library(db_path):
        data = read_links(agent_id, db_path)
        if data.get('links'):
            result.append({'id': agent_id, 'links': data['links']})
    return {'agents': result}


def cmd_generate_split(args):
    result = generate_split_file(
        agent_id=args.id,
        db_path=args.db,
        platform=args.platform,
    )
    if 'error' in result:
        print(_dump(result))
        sys.exit(result.get('exit_code', 2))
    print(_dump(result))


def cmd_read_links(args):
    result = read_links(agent_id=args.id, db_path=args.db)
    print(_dump(result))


def cmd_write_links(args):
    try:
        links = json.loads(args.links_json)
    except Exception as e:
        print(_dump({'error': f'Invalid JSON for links: {e}', 'exit_code': 2}))
        sys.exit(2)
    result = write_links(agent_id=args.id, db_path=args.db, links=links)
    print(_dump(result))


def cmd_list_all_links(args):
    result = list_all_links(db_path=args.db)
    print(_dump(result))


def cmd_generate_runtime(args):
    result = generate_runtime_content(
        agent_id=args.id,
        db_path=args.db,
        platform=args.platform,
    )
    if 'error' in result:
        print(_dump(result))
        sys.exit(result.get('exit_code', 2))
    print(_dump(result))


def cmd_list_agents(args):
    result = list_agents(args.db)
    print(_dump(result))


def cmd_list_skills(args):
    result = list_skills(args.db)
    print(_dump(result))


def cmd_list_categories(args):
    result = list_categories(args.db)
    print(_dump(result))


def cmd_status_agents(args):
    result = status_agents(
        db_path=args.db,
        platform=args.platform,
        runtime_dir=getattr(args, 'runtime_dir', '') or '',
    )
    print(_dump(result))


def cmd_status_skills(args):
    result = status_skills(
        db_path=args.db,
        platform=getattr(args, 'platform', '') or '',
        runtime_dir=getattr(args, 'runtime_dir', '') or '',
    )
    print(_dump(result))


def cmd_github_diff(args):
    result = github_diff_agent(
        agent_id=args.id,
        db_path=args.db,
        github_dir=args.github_dir,
        entity=getattr(args, 'entity', 'agents') or 'agents',
    )
    in_sync = result.get('in_sync', False)
    print(_dump(result))
    if not in_sync:
        sys.exit(1)


def cmd_github_status(args):
    result = github_status_agents(
        db_path=args.db,
        github_clone_dir=args.clone_dir,
        github_mode=args.github_mode,
        entity=getattr(args, 'entity', 'agents') or 'agents',
    )
    print(_dump(result))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='apm Python helper — outputs JSON')
    subparsers = parser.add_subparsers(dest='command')

    # parse-root
    p = subparsers.add_parser('parse-root')
    p.add_argument('file')

    # parse-runtime
    p = subparsers.add_parser('parse-runtime')
    p.add_argument('file')

    # build-manifest
    p = subparsers.add_parser('build-manifest')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)
    p.add_argument('--runtime-dir', default='')
    p.add_argument('--github-mode', default='')
    p.add_argument('--github-owner', default='')
    p.add_argument('--github-repo', default='')
    p.add_argument('--github-branch', default='')

    # validate-agent
    p = subparsers.add_parser('validate-agent')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)

    # validate-all
    p = subparsers.add_parser('validate-all')
    p.add_argument('--db', required=True)

    # diff-manifest
    p = subparsers.add_parser('diff-manifest')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)
    p.add_argument('--runtime-dir', default='')

    # list-agents
    p = subparsers.add_parser('list-agents')
    p.add_argument('--db', required=True)

    # list-skills
    p = subparsers.add_parser('list-skills')
    p.add_argument('--db', required=True)

    # list-categories
    p = subparsers.add_parser('list-categories')
    p.add_argument('--db', required=True)

    # status-agents
    p = subparsers.add_parser('status-agents')
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)
    p.add_argument('--runtime-dir', default='')

    # status-skills
    p = subparsers.add_parser('status-skills')
    p.add_argument('--db', required=True)
    p.add_argument('--platform', default='')
    p.add_argument('--runtime-dir', default='')

    # generate-runtime
    p = subparsers.add_parser('generate-runtime')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)

    # analyze-import
    p = subparsers.add_parser('analyze-import')
    p.add_argument('file')
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)

    # build-import-draft
    p = subparsers.add_parser('build-import-draft')
    p.add_argument('file')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)
    p.add_argument('--timestamp', required=True)

    # generate-split
    p = subparsers.add_parser('generate-split')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--platform', required=True)

    # read-links
    p = subparsers.add_parser('read-links')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)

    # write-links
    p = subparsers.add_parser('write-links')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--links-json', required=True)

    # list-all-links
    p = subparsers.add_parser('list-all-links')
    p.add_argument('--db', required=True)

    # scan-unmanaged
    p = subparsers.add_parser('scan-unmanaged')
    p.add_argument('--runtime-dir', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--ignore-file', default='')

    # github-diff: compare canonical library agent dir vs a cloned repo dir
    p = subparsers.add_parser('github-diff')
    p.add_argument('--id', required=True)
    p.add_argument('--db', required=True)
    p.add_argument('--github-dir', required=True)
    p.add_argument('--entity', default='agents')

    # github-status: per-agent github sync state across library
    p = subparsers.add_parser('github-status')
    p.add_argument('--db', required=True)
    p.add_argument('--clone-dir', required=True)
    p.add_argument('--github-mode', default='monorepo')
    p.add_argument('--entity', default='agents')

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(2)

    dispatch = {
        'parse-root': cmd_parse_root,
        'parse-runtime': cmd_parse_runtime,
        'build-manifest': cmd_build_manifest,
        'validate-agent': cmd_validate_agent,
        'validate-all': cmd_validate_all,
        'diff-manifest': cmd_diff_manifest,
        'list-agents': cmd_list_agents,
        'list-skills': cmd_list_skills,
        'list-categories': cmd_list_categories,
        'status-agents': cmd_status_agents,
        'status-skills': cmd_status_skills,
        'generate-runtime': cmd_generate_runtime,
        'analyze-import': cmd_analyze_import,
        'build-import-draft': cmd_build_import_draft,
        'scan-unmanaged': cmd_scan_unmanaged,
        'generate-split': cmd_generate_split,
        'read-links': cmd_read_links,
        'write-links': cmd_write_links,
        'list-all-links': cmd_list_all_links,
        'github-diff': cmd_github_diff,
        'github-status': cmd_github_status,
    }

    fn = dispatch.get(args.command)
    if fn:
        try:
            fn(args)
        except Exception as e:
            print(_dump({'error': str(e), 'command': args.command, 'exit_code': 2}))
            sys.exit(2)
    else:
        print(_dump({'error': f'Unknown command: {args.command}', 'exit_code': 2}))
        sys.exit(2)


if __name__ == '__main__':
    main()
