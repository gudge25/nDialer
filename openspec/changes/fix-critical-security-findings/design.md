## Context

Django 1.7.7 (see `requirements/django.txt`), so `django.db.models.functions` (`Cast`, `Substr`, available from Django 1.8) is not usable — any `.extra()` replacement must use ORM lookups available in 1.7, or plain parameterized SQL. `settings.py` already supports a local override file: it ends with `try: from settings_local import *; except ImportError: pass`, so any setting assigned earlier in `settings.py` is already overridable by a deployment's `settings_local.py` without further wiring. See proposal.md for the full list of affected files and motivation.

## Goals / Non-Goals

**Goals:**
- Eliminate the 6 exploitable SQL-injection call sites (attacker-controlled `getlist()` values reaching `.extra(where=...)`).
- Remove the plaintext `SECRET_KEY` from source in a way that doesn't break existing deployments that haven't set new configuration yet.
- Leave a clear, auditable trail (code comments + Sonar hotspot review) for the SQL-injection hotspots that are not user-reachable, so they don't reappear as "unreviewed" in future scans.

**Non-Goals:**
- Rewriting `.extra(select=...)` date-truncation queries to avoid `.extra()` entirely (blocked by Django 1.8+ requirement for `Cast`/`Substr`; out of scope for a security stopgap).
- Changing the sqlite3-vs-postgres deployment story, adding secrets-manager integration, or introducing a settings/config framework — this only closes the specific Sonar-flagged gaps.
- Fixing the 12 hardcoded-"password"-string majors, the 4 blocker bugs, or the XSS hotspots — explicitly out of scope for this change per user selection.

## Decisions

**1. `SECRET_KEY`: env var with an explicitly-insecure fallback, not a hard failure.**
`SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', '<new-dev-only-fallback>')`. Alternative considered: raise `ImproperlyConfigured` if unset. Rejected because this codebase has no environment-tiering mechanism (no `DEBUG`-gated strictness) and existing installs (per the CVE-2019-19844 stopgap precedent in this repo) are patched in place without a guaranteed deployment/config step; a hard failure would turn a security fix into an outage for any environment that doesn't set the env var before upgrading. The fallback value is freshly generated (not the old compromised key) and named/commented as dev-only. `install/conf/settings_local.py` (the template admins copy for real deployments) gets an explicit `SECRET_KEY = '...'` line with instructions to generate a unique value, so the documented production path never relies on the fallback.

**2. Multi-delete/count endpoints: validate to `int`, then use ORM `__in`.**
Replace:
```python
values = request.POST.getlist('select')
values = ", ".join(["%s" % el for el in values])
...extra(where=['id IN (%s)' % values])
```
with:
```python
ids = [int(v) for v in request.POST.getlist('select') if v.isdigit()]
...filter(id__in=ids)
```
Alternative considered: keep `.extra()` but pass `values` as a query parameter placeholder list. Rejected — Django's `.extra(where=..., params=...)` still requires manually matching `%s` placeholder count to a dynamic-length `IN (...)` list, which is more error-prone than the ORM's `__in` lookup and provides no behavioral benefit here. `__in` is simpler, is what Django recommends for this exact case, and silently drops non-numeric entries (matching the spec's "ignore invalid entries" scenario) instead of ever reaching a query.

**3. Raw SQL (`cursor.execute`, `Model.objects.raw`): parameterize with `%s` + params list.**
`campaign_id`/`phonebook_id` are already implicitly guarded by the `%d` string-format operator (a non-numeric value raises `TypeError` before reaching the DB), so these are lower actual risk than the `.extra()` sites, but the fix is small and removes the hotspot cleanly: replace `%d`/string-concatenation with `%s` placeholders and pass values via the `params` argument (`cursor.execute(sql, [campaign_id, phonebook_id, ...])`, `Model.objects.raw(query, [self.id, self.id])`).
`dialer_contact/tasks.py`'s `limit_import` (a `'LIMIT <int>'`/`'LIMIT 0'`/`''` fragment) was initially left as string-concatenated literal text since it isn't a single bindable scalar — but SonarQube's PR analysis correctly flagged that concatenation pattern as a new hotspot regardless of the value's origin. Resolved properly instead of reviewing it away: the SQL now always contains a literal `LIMIT %s`, and the Python side computes a single `limit_value` (an int, or `None`) passed as a normal bound parameter — `LIMIT NULL` is equivalent to omitting `LIMIT` in PostgreSQL, so this covers the "no cap configured" case too. No SQL string-building remains in this function.

**4. `.extra(select=...)` date-truncation hotspots (frontend/views.py, mod_sms/views.py) and the sqlite3 DB-password hotspot: resolve via Sonar hotspot review, not code change.**
`date_length` is assigned one of three hardcoded literals (10, 13, 16) earlier in the same function — never derived from request data — so there is no injection path to fix. Add a one-line comment at each site stating this explicitly (`# date_length is one of {10,13,16} set above; not user-controlled`), and mark the corresponding SonarQube hotspots "Safe" with that justification. Likewise, sqlite3 has no username/password concept, so `settings.py`'s empty `USER`/`PASSWORD` fields for the default sqlite3 config are correct, not a gap — add a clarifying comment and resolve that finding as a false positive rather than fabricating credentials sqlite3 would ignore.

## Risks / Trade-offs

- [Rotating `SECRET_KEY` invalidates all existing signed sessions and CSRF-signed content on every environment simultaneously] → Mitigation: this is an accepted, disclosed break (see proposal.md, marked BREAKING); users are simply logged out and must log in again, no data loss. Deploy during a low-traffic window.
- [Non-numeric IDs are now silently dropped instead of hitting the database at all] → Mitigation: this matches current effective behavior for well-formed requests (all current callers pass numeric IDs from checkboxes/hidden inputs) and only changes behavior for malformed/malicious input, which previously reached raw SQL.
- [Old committed `SECRET_KEY` remains visible in git history even after rotation] → Mitigation: out of scope to rewrite history; the key is treated as permanently compromised and simply retired, not reused.
- [Marking hotspots "Safe" in SonarQube instead of changing code relies on human judgment about "not user-controlled" holding true over time] → Mitigation: the accompanying inline code comment travels with the code, so a future change that makes `date_length` request-derived will sit next to a comment explaining the original safety assumption, making the risk visible to the next author.

## Migration Plan

1. Land the code changes (settings, views, tasks, models) together in one change, since they share the review/deploy window.
2. Generate a new random `SECRET_KEY` for the dev-fallback constant; document in `install/conf/settings_local.py` that production must set its own via `DJANGO_SECRET_KEY` or a `settings_local.py` override.
3. Deploy; expect all active sessions to be invalidated (see Risks).
4. In SonarQube, mark the 4 `date_length` hotspots as "Safe" and resolve the sqlite3-password vulnerability as a false positive, with the justification from Decision 4, referencing this change.
5. Re-run analysis and confirm BLOCKER vulnerabilities = 0 and HIGH SQL-injection hotspots = 0 for this scope.

Rollback: revert the commit(s); this reintroduces the known vulnerabilities but no schema/data migration is involved, so rollback is a plain code revert.
