```
□ OBSERVED   what was wrong or missing
+ REPAIRED   what this changes
✓ VERIFIED   tests run (test_local, dbt parse per connector, walkthrough)
× OPEN       what this does not cover
```

- [ ] Synthetic data only; no client data or credentials
- [ ] `python3 scripts/test_local.py` passes
- [ ] `dbt parse` passes for native, fivetran and airbyte
- [ ] Decision recorded in `DECISIONS.md` if behavior changed
