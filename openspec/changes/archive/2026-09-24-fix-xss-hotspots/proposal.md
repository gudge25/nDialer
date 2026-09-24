## Why

This change closes the remaining SonarQube findings that matter most now that the BLOCKER vulnerabilities and SQL-injection hotspots are fixed (see the archived `fix-critical-security-findings` change): the 13 HIGH-probability XSS hotspots, the 4 BLOCKER bugs, and the 12 MAJOR "hardcoded password" findings.

- **XSS**: SonarQube flags 13 HIGH-probability XSS hotspots across 6 templates, all from `|safe` filter usage. Investigating each one's actual data source shows 12 are false positives (the underlying value is always an integer ID, a Django-setting-sourced static string, or text Django itself already HTML-escaped before this code ever sees it), but one is a real stored-XSS vulnerability: `survey/templatetags/survey_tags.py`'s `get_branching_goto_field` interpolates a survey section's free-text `question`/`script` field — content a survey author enters through the admin UI — directly into an `<option>` tag's label with no escaping, then the template marks the whole result `|safe`. Anyone who can create/edit a survey section can inject `<script>`/HTML that executes for every other user who later opens that survey's branching editor.
- **BLOCKER bugs**: 4 identical `python:S2159` findings ("equality check between incompatible types; it will always return False") in `dialer_contact/admin.py`, `dnc/views.py`, `dialer_contact/views.py`, and `survey/views.py`. Each is the same CSV-import row-skip guard, `if not row or str(row[0]) == 0:`, comparing a `str` to the `int` literal `0` — a comparison that is always `False` in Python regardless of the row's actual content, so rows whose first column is the string `"0"` are never skipped as the code clearly intends.
- **Hardcoded-password findings**: 12 `python:S2068` findings ("'password' detected here, review this potentially hard-coded credential") across `settings.py`/`settings_local.py` (Acapela TTS placeholder credentials, all-`X` dummy values), `agent/serializers.py` (a `<hidden>` display-masking constant, not a credential), `agent/backup_code.py` and `frontend/tests.py` (Django test-client login calls with throwaway test passwords), and `newfies_factory/factories.py` (FactoryBoy test-data factories, imported only by `appointment/tests.py`). None of these are real, live credentials.

## What Changes

- `survey/templatetags/survey_tags.py`'s `get_branching_goto_field` HTML-escapes the section's `question`/`script` text before interpolating it into the `<option>` label, closing the stored-XSS vector.
- The remaining 12 XSS hotspots are resolved in SonarQube as reviewed/Safe, each with a code comment recording why, rather than code changes (there is no unescaped user input flowing through them):
  - `agent/templates/agent/agent_detail.html` (2): `field.errors` is already HTML-escaped by Django's own `ErrorList.as_ul()` (via `format_html`/`format_html_join`) before this template's `|removetags|safe` runs; the `|safe` here is required to avoid double-escaping the entities Django already produced, not a bypass.
  - `agent/templates/agent/login.html` (1): `user_json` is never set by any view in this codebase — the variable always renders empty, so there is no live data path to exploit today.
  - `dialer_campaign/templates/dialer_campaign/campaign/list.html` (2) and `mod_sms/templates/mod_sms/list.html` (3): `get_campaign_status`/`get_sms_campaign_status` key off an integer status code against a fixed color/label map; `create_duplicate_campaign`/`create_duplicate_sms_campaign`/`get_sms_campaign_textmessage` interpolate only an integer primary key (`row.id`) and a static translated title into a fixed link template — no free-text user input reaches any of them.
  - `templates/pagination/pagination.html` (4): `previous_link_decorator`/`next_link_decorator` come from `linaro-django-pagination`'s `PAGINATION_PREVIOUS_LINK_DECORATOR`/`PAGINATION_NEXT_LINK_DECORATOR` Django settings (deployment-time config, defaulting to static HTML-entity arrows), never from a request.
- The 4 `str(row[0]) == 0` CSV-import guards are fixed to `str(row[0]) == '0'` in `dialer_contact/admin.py`, `dnc/views.py`, `dialer_contact/views.py`, and `survey/views.py`, so rows whose first CSV column is `"0"` are actually skipped as intended.
- All 12 hardcoded-password findings are resolved in SonarQube as false positives, each with a short comment recording why (placeholder/dummy value, or test-only fixture data) — no code changes, since none of them are real credentials.

## Capabilities

### New Capabilities
- `template-output-safety`: User-authored free-text content rendered into HTML templates must be escaped before being marked safe/unescaped for output.
- `csv-import-row-validation`: CSV bulk-import handlers must correctly recognize and skip placeholder/blank leading-column rows.

### Modified Capabilities
(none — no existing capability's requirements change)

## Impact

- **Code**:
  - XSS: `newfies/survey/templatetags/survey_tags.py` (escape fix); `newfies/agent/templates/agent/agent_detail.html`, `newfies/agent/templates/agent/login.html`, `newfies/dialer_campaign/templatetags/dialer_campaign_tags.py`, `newfies/mod_sms/templatetags/mod_sms_tags.py`, `newfies/templates/pagination/pagination.html` (comments only, no behavior change).
  - Blocker bugs: `newfies/dialer_contact/admin.py`, `newfies/dnc/views.py`, `newfies/dialer_contact/views.py`, `newfies/survey/views.py` (one-character fix each).
  - Hardcoded-password findings: `install/conf/settings_local.py`, `newfies/newfies_dialer/settings.py`, `newfies/agent/serializers.py`, `newfies/agent/backup_code.py`, `newfies/frontend/tests.py`, `newfies/newfies_factory/factories.py` (comments only, no behavior change).
- **SonarQube**: reduces HIGH-probability XSS hotspots from 13 to 0 (1 resolved by code fix, 12 resolved via hotspot review as Safe), BLOCKER bugs from 4 to 0, and MAJOR vulnerabilities from 12 to 0 (all 12 resolved as false positives).
- **Tests**: the survey branching-goto dropdown needs regression coverage confirming section question/script text renders as visible (escaped) text instead of executing, for a value containing HTML-special characters. The CSV-import row-skip fix needs regression coverage confirming a row whose first column is `"0"` is skipped rather than processed, for each of the 4 affected import paths.
