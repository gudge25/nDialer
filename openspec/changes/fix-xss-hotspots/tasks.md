## 1. Fix the real stored-XSS vector

- [x] 1.1 In `newfies/survey/templatetags/survey_tags.py`'s `get_branching_goto_field`, HTML-escape `q_string` (from `i.question` or `i.script`) via `django.utils.html.escape` before it's interpolated into either `<option>` branch; verify by reading the escaped value is used in both the "selected" and "not selected" option strings.
- [x] 1.2 Add/adjust a test that creates a survey section with a `question` (or `script`) value containing `<`, `>`, and `&`, calls `get_branching_goto_field`, and asserts the returned HTML contains the escaped form (`&lt;`, `&gt;`, `&amp;`) and not the raw characters; verify by running the test. [Added `test_get_branching_goto_field_escapes_question_text` in `newfies/survey/tests.py`; test run pending in section 5.]

## 2. Document the 12 false-positive hotspots

- [x] 2.1 Add a one-line comment above the `field.errors|removetags:"ul li"|safe` line in both spots in `newfies/agent/templates/agent/agent_detail.html` noting Django's `ErrorList.as_ul()` already HTML-escapes each error message, so `|safe` here avoids double-escaping rather than bypassing escaping; verify by reading the comment sits directly above each site.
- [x] 2.2 Add a one-line comment above `$rootScope.user = {{user_json|safe}};` in `newfies/agent/templates/agent/login.html` noting no view in this codebase sets `user_json`, so it always renders empty; verify by reading the comment is present. [Also discovered and noted: the whole block is inside a JS `/* */` comment, so it never executes regardless.]
- [x] 2.3 Add a one-line comment above `get_campaign_status`/`create_duplicate_campaign` in `newfies/dialer_campaign/templatetags/dialer_campaign_tags.py` noting they only ever receive an integer status code or primary key, never free text; verify by reading the comments are present above both functions.
- [x] 2.4 Add a one-line comment above `get_sms_campaign_status`/`create_duplicate_sms_campaign`/`get_sms_campaign_textmessage` in `newfies/mod_sms/templatetags/mod_sms_tags.py` noting the same (integer status code / primary key only); verify by reading the comments are present above all three functions.
- [x] 2.5 Add a one-line comment above the `previous_link_decorator`/`next_link_decorator` usages in `newfies/templates/pagination/pagination.html` noting they come from `linaro-django-pagination`'s `PAGINATION_PREVIOUS_LINK_DECORATOR`/`PAGINATION_NEXT_LINK_DECORATOR` Django settings, not request data; verify by reading the comment is present.
- [ ] 2.6 In SonarQube, mark the 12 corresponding hotspots (agent_detail.html:31/47, login.html:22, campaign/list.html:82/92, mod_sms/list.html:72/81/83, pagination.html:11/14/37/40) as reviewed/"Safe" with a short justification referencing this change; verify by reloading the project dashboard and confirming these no longer appear as TO_REVIEW/open.

## 3. Fix the 4 BLOCKER bugs (CSV import row-skip)

- [x] 3.1 In `newfies/dialer_contact/admin.py`, change `if not row or str(row[0]) == 0:` to `if not row or str(row[0]) == '0':`; verify by reading the literal is now a string.
- [x] 3.2 Make the same fix in `newfies/dnc/views.py`; verify by reading the literal is now a string.
- [x] 3.3 Make the same fix in `newfies/dialer_contact/views.py`; verify by reading the literal is now a string.
- [x] 3.4 Make the same fix in `newfies/survey/views.py`; verify by reading the literal is now a string.
- [x] 3.5 Add or extend a test per file (4 total) that submits/imports a CSV row whose first column is `"0"` and asserts it is skipped (not processed as data) rather than causing an error or an incorrect record; verify by running the tests. [Added `test_dnc_contact_import_skips_zero_marker_row` (dnc/tests.py), `test_contact_import_skips_zero_marker_row` + `test_admin_contact_import_skips_zero_marker_row` (dialer_contact/tests.py — the latter replaces a previously-commented-out, non-functional attempt at the same admin path), `test_import_survey_skips_zero_marker_row` (survey/tests.py). Test run pending in section 5.]

## 4. Document the 12 hardcoded-password findings

- [x] 4.1 Add a one-line comment above the `APPLICATION_PASSWORD = 'XXXXXXXX'` line in `install/conf/settings_local.py` and `newfies/newfies_dialer/settings.py` noting it's an all-X Acapela TTS placeholder, not a real credential; verify by reading the comments are present above both sites.
- [x] 4.2 Add a one-line comment above `HIDDEN_PASSWORD_STRING = '<hidden>'` in `newfies/agent/serializers.py` noting it's a display-masking constant, not a credential; verify by reading the comment is present.
- [x] 4.3 Add a one-line comment above the hardcoded test-login credentials in `newfies/agent/backup_code.py` (2 sites) and `newfies/frontend/tests.py` (4 sites) noting these are Django test-client calls against a per-test in-memory database, not real accounts; verify by reading the comments are present above all 6 sites.
- [x] 4.4 Add a one-line comment above each `password = '1234'` in `newfies/newfies_factory/factories.py` (3 sites) noting these FactoryBoy factories are imported only by `appointment/tests.py` (confirmed via repo-wide grep), never used to seed production data; verify by reading the comments are present above all 3 sites. [Caught and fixed a self-inflicted `replace_all` mistake: it initially also matched a 4th, unrelated, already-commented-out `password = '1234'` inside a dead `# class UserFactory` block, partially uncommenting it. Restored that block to its original state; it is not one of the 12 Sonar findings.]
- [ ] 4.5 In SonarQube, resolve the 12 corresponding hardcoded-password issues (settings_local.py:183, backup_code.py:78/79, serializers.py:19, factories.py:97/127/192, frontend/tests.py:34/56/61/75, settings.py:561) as false positive/won't-fix with a short justification referencing this change; verify by reloading the project dashboard and confirming these no longer appear as open.

## 5. Verification

- [ ] 5.1 Re-run the project's Python test suite and confirm no regressions, including the new survey branching-goto escaping test and the 4 CSV-import row-skip tests; verify via the test runner's pass/fail output (run for real via CI, not simulated).
- [ ] 5.2 Trigger a SonarQube re-analysis (via a real PR, as in the prior change) and confirm: 0 open HIGH-probability XSS hotspots, 0 BLOCKER bugs, 0 open MAJOR vulnerabilities, quality gate OK, 0 new violations; verify by comparing the new dashboard/PR analysis counts against the baseline captured in this change's proposal.
