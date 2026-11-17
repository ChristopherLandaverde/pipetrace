# Decisions

- Build the supplied PDF as the contract; retain its requested layer and filenames while correcting unsafe SQL. User explicitly requested this repository.
- Use Python/SQL/dbt for a data pipeline despite application defaults; they match the requested BigQuery stack.
- Use a new isolated local repository on build/semantic-warehouse. No existing main checkout is modified and no public remote is created.
- Rebuild configured observation-window tables in v1. This handles late arrivals, deletions and CRM corrections without stale incremental allocations. Window and cost limits are documented.
- Use session ID seconds for the stable session-start date, property timezone, and a raw boundary buffer. Finite buffers cannot capture arbitrarily long sessions.
- Select an attribution struct as a unit; never replace session source with lifetime acquisition.
- Keep every conversion token and rank deterministic ID paths. Do not join email or expand a contact-role many-to-many join.
- Preserve unmatched opportunities, allocate them to Unattributed, and conserve opportunity value in both weight models.
- Keep ARR separate from Amount, and retain currency/revenue_basis in all aggregate revenue surfaces.
- Add Python standard-library relational acceptance tests because local package downloads are blocked. These execute actual CRM/attribution SQL with narrowly documented dialect substitutions; native BigQuery tests remain mandatory.
- Treat the README's Readable Layer as governed SQL tables, not an implicitly deployed dbt Semantic Layer service.
