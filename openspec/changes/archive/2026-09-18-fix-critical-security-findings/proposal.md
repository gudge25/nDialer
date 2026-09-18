## Why

SonarQube's latest analysis of nDialer (https://sonar.gixo.co.uk/dashboard?id=nDialer) flags two BLOCKER vulnerabilities and 13 HIGH-probability SQL-injection hotspots. The Django `SECRET_KEY` is committed in plaintext in `newfies/newfies_dialer/settings.py`, and six request handlers build raw SQL `WHERE ... IN (...)` clauses by string-joining attacker-controlled list values (`request.GET.getlist(...)` / `request.POST.getlist(...)`) with no parameterization or type validation, which is exploitable SQL injection. These are addressed now, ahead of the lower-severity bug/major-vulnerability backlog, because they are directly exploitable or directly compromise the application's cryptographic foundation (session/CSRF signing).

## What Changes

- **BREAKING**: `SECRET_KEY` in `newfies/newfies_dialer/settings.py` is rotated (the current value is public in git history and must be treated as compromised) and sourced from an environment variable (`DJANGO_SECRET_KEY`) with a clearly-marked insecure fallback for local/dev bootstrap only. Any deployment relying on the old hardcoded value must set the environment variable or override `SECRET_KEY` in `settings_local.py` — existing sessions/signed cookies will be invalidated on rollout.
- Six request handlers that build `.extra(where=['... IN (%s)' % values])` from `request.GET`/`request.POST` list input are rewritten to use Django ORM `__in` filters against integer-validated values, removing the SQL injection vector entirely:
  - `newfies/dialer_contact/views.py` (`get_contact_count`, `phonebook_del`, `contact_del_list`)
  - `newfies/mod_sms/views.py` (`smscampaign_del`/multi-delete branch)
  - `newfies/survey/views.py` (survey multi-delete branch)
- `newfies/mod_sms/models.py`'s `Contact.objects.raw(query)` call is switched from string-formatted values to parameterized `raw(query, params)`.
- `cursor.execute(sqlimport)` calls in `newfies/dialer_contact/tasks.py` and `newfies/mod_sms/tasks.py` are switched from `%d`-interpolated SQL strings to parameterized `cursor.execute(sql, params)`.
- The remaining SQL-injection hotspots (`.extra(select=...)` in `newfies/frontend/views.py` and `newfies/mod_sms/views.py`, built from an internal 3-valued constant `date_length`, never user input) and the DB-password hotspot on the default sqlite3 config (`newfies/newfies_dialer/settings.py`, sqlite3 has no username/password concept) are documented as reviewed-safe rather than code-changed; marking them "Safe" in SonarQube is a task in this change.
- No new user-facing behavior; this is a security-hardening change to existing capabilities.

## Capabilities

### New Capabilities
- `secure-app-configuration`: The application's cryptographic secret (`SECRET_KEY`) must not be committed to source control and must be sourced from deployment configuration.
- `sql-query-safety`: User-supplied list/identifier input used to build phonebook, contact, SMS campaign, and survey deletion/count queries must be validated and parameterized, never string-interpolated into raw SQL or `.extra()` clauses.

### Modified Capabilities
(none — no existing capability's requirements change)

## Impact

- **Code**: `newfies/newfies_dialer/settings.py`, `install/conf/settings_local.py` (add `SECRET_KEY` placeholder/documentation), `newfies/dialer_contact/views.py`, `newfies/dialer_contact/tasks.py`, `newfies/mod_sms/views.py`, `newfies/mod_sms/models.py`, `newfies/mod_sms/tasks.py`, `newfies/survey/views.py`.
- **Deployments**: every environment must set `DJANGO_SECRET_KEY` (or override `SECRET_KEY` in its `settings_local.py`) before/at rollout, or the app falls back to a clearly-insecure dev key. All existing signed sessions/cookies are invalidated when the key rotates.
- **SonarQube**: reduces BLOCKER vulnerability count from 2 to 0 (both resolved by code fix) and HIGH SQL-injection hotspots from 13 to 0 (9 resolved by code fix, 4 resolved via hotspot review as Safe with recorded justification).
- **Tests**: existing contact/phonebook/SMS-campaign/survey delete and count views need regression coverage for the new `__in`-based filtering (equivalent behavior, non-numeric input now rejected instead of silently reaching raw SQL).
