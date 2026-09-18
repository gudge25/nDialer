## Context

See proposal.md for the per-hotspot data-flow analysis, the 4 blocker-bug locations, and the 12 hardcoded-password locations. One XSS finding needs a code fix; twelve are false positives Sonar cannot distinguish via static pattern-matching alone (it flags any `|safe` filter regardless of whether the underlying value can ever contain attacker-influenced HTML). This mirrors the `date_length`/sqlite3-password false positives handled the same way in the prior `fix-critical-security-findings` change. The 4 blocker bugs are all the exact same one-line logic error, copy-pasted across 4 CSV-import handlers. The 12 hardcoded-password findings are all either placeholder/dummy values or test-only fixture data — none are real credentials.

## Goals / Non-Goals

**Goals:**
- Close the one real stored-XSS vector (`get_branching_goto_field`) with a minimal, targeted escape.
- Fix the 4 identical `str(row[0]) == 0` blocker bugs so the intended skip-condition actually fires.
- Leave an auditable trail (code comment + Sonar hotspot/issue review) for the 12 XSS false positives and the 12 hardcoded-password false positives, so they don't reappear as "unreviewed" in future scans, and so a future change that turns one of these values into something real has a comment nearby explaining the original safety assumption.

**Non-Goals:**
- Rewriting these templates/filters to avoid `|safe` entirely (e.g. switching to Django's auto-escaping-friendly template constructs) — out of scope for a targeted hotspot closure; several of these `|safe` usages are load-bearing (HTML entities, pre-escaped Django output) and removing them would break rendering.
- Fixing the 1 MINOR cookie vulnerability, or any other Sonar finding not selected for this change.
- Switching `newfies_factory/factories.py`'s test-only `UserFactory`/`ManagerFactory`/`CalendarUserFactory` to hash their placeholder password via Django's password-hashing machinery — a legitimate test-hygiene improvement, but unrelated to the Sonar finding (which flags the literal string, not how it's applied) and out of scope here.

## Decisions

**1. `get_branching_goto_field`: escape with `django.utils.html.escape` before interpolation.**
```python
from django.utils.html import escape
...
q_string = escape(q_string)
```
applied once after computing `q_string` (whether from `i.question` or `i.script`), before it's used in the `%s` formatting for both the "selected" and "not selected" `<option>` branches. Alternative considered: mark the return value safe only at specific call sites in the template instead of escaping in the filter. Rejected — the filter is the single place this value is ever produced, escaping there closes the vector regardless of future template changes, and matches where the other filters in this codebase already do their own HTML construction.

**2. XSS false positives: comment + Sonar hotspot review, not code changes.**
Same approach as the prior change's `date_length` hotspots: a short comment at each site stating why the value can't carry attacker-controlled HTML, then mark the hotspot "Safe" in SonarQube referencing this change. Rewriting `agent_detail.html`'s error rendering or the pagination decorators to avoid `|safe` would either break the escaping Django already performs (double-escaping error entities) or break the HTML-entity arrows pagination relies on — not worth the churn for hotspots with no real vector.

**3. Blocker bugs: fix the literal, `== 0` to `== '0'`, at all 4 sites.**
`if not row or str(row[0]) == 0:` — `str(row[0])` is always a `str`, so comparing it to the `int` literal `0` is always `False` in Python regardless of content; that's exactly what `python:S2159` flags. The evident intent, given it's `or`-ed with the "row is empty" check, is "treat a row whose first column is `'0'` the same as an empty row." Alternative considered: change the comparison to `row[0] in ('0', 0)` to also tolerate a genuinely-int-typed first column. Rejected — `row[0]` comes from `csv.reader`, which always yields `str` values, so an `int` never reaches this comparison; matching the existing string-comparison style (`== '0'`) is the smallest, most direct fix for what the code actually receives.

**4. Hardcoded-password findings: comment + Sonar issue review (false positive/won't-fix), not code changes.**
`install/conf/settings_local.py`/`newfies_dialer/settings.py`'s `APPLICATION_PASSWORD = 'XXXXXXXX'` is an all-`X` Acapela TTS placeholder (same pattern as the `ACCOUNT_LOGIN`/`APPLICATION_LOGIN` placeholders right next to it, already established as safe-to-keep-as-literal in this codebase). `agent/serializers.py`'s `HIDDEN_PASSWORD_STRING = '<hidden>'` is a display-masking constant, not a credential. `agent/backup_code.py` and `frontend/tests.py`'s hardcoded values are Django test-client `login()`/POST calls against an in-memory test database created fresh per test run — there is no real account these credentials grant access to. `newfies_factory/factories.py`'s `password = '1234'` fields are FactoryBoy test-data factories imported only by `appointment/tests.py` (confirmed via repo-wide grep) — never used to seed production data. None of the 12 need a code change; all get a comment plus a SonarQube issue resolution.

## Risks / Trade-offs

- [`escape()` changes the literal bytes rendered for section question/script text containing `<`, `>`, `&`, `"`, `'`] → Mitigation: this is exactly the intended fix — such text was previously rendered as raw (and exploitable) HTML; after this change it renders as visible escaped text, which is the correct, safe behavior. Any survey currently relying on literal HTML in a question/script to render as HTML (an unlikely and already-unsafe pattern) would see that stop working — acceptable given it's an XSS vector today.
- [Reviewing 12 XSS hotspots and 12 hardcoded-password findings as "Safe"/false-positive relies on the data-flow analysis in proposal.md holding over time] → Mitigation: same as the prior change — each reviewed site gets an inline comment explaining the assumption, so a future change that makes one of these values real (e.g. a factory password reused outside tests, or a pagination decorator setting sourced from request data) has a comment right there flagging the risk.
- [Fixing `== 0` to `== '0'` changes which rows 4 different CSV import handlers silently skip] → Mitigation: this only changes behavior for rows whose first column is literally `"0"` (previously processed as data despite evident intent to skip them); every other row's behavior is unchanged. Each of the 4 sites gets a regression test covering exactly this row.

## Migration Plan

1. Land the `get_branching_goto_field` escape fix, the 4 blocker-bug one-character fixes, and all the review comments together (small, low-risk diff — no schema/data migration, no session impact, unlike the prior change's SECRET_KEY rotation).
2. Add/adjust tests: branching-goto HTML-escaping, and one "first column is '0' gets skipped" case per CSV-import handler.
3. Deploy.
4. In SonarQube, mark the 12 XSS false-positive hotspots "Safe" and the 12 hardcoded-password findings as false positive/won't-fix, each with justification referencing this change.
5. Re-run analysis and confirm 0 open HIGH-probability XSS hotspots, 0 BLOCKER bugs, 0 open MAJOR vulnerabilities.

Rollback: plain code revert; no data/schema involved.
