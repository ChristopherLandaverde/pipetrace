{#- Print the readiness checks after a build:
      dbt build && dbt run-operation pipetrace_doctor -#}
{% macro pipetrace_doctor() %}
  {% if not execute %}{{ return('') }}{% endif %}
  {% set relation = ref('pipetrace_readiness') %}
  {% set existing = adapter.get_relation(database=relation.database, schema=relation.schema, identifier=relation.identifier) %}
  {% if existing is none %}
    {{ exceptions.raise_compiler_error('pipetrace_readiness not found in ' ~ relation ~ '. Run dbt build first.') }}
  {% endif %}
  {% set results = run_query('select area, check_name, description, numerator, denominator, share, status, guide_section from ' ~ relation ~ ' order by check_order') %}
  {% set marks = {'ok': '✓', 'low': '!', 'missing': '×', 'review': '!', 'no_rows': '·', 'off': '-'} %}
  {{ print('PipeTrace readiness · ' ~ relation) }}
  {% set ns = namespace(area='', next=[]) %}
  {% for row in results.rows %}
    {% if row['area'] != ns.area %}{{ print('') }}{{ print(row['area'] | upper) }}{% set ns.area = row['area'] %}{% endif %}
    {% set count = row['numerator'] | string ~ ((' of ' ~ row['denominator'] | string) if row['denominator'] is not none else '') %}
    {% set pct = (' (' ~ ((row['share'] * 100) | round(1)) ~ '%)') if row['share'] is not none else '' %}
    {{ print('  ' ~ marks.get(row['status'], '?') ~ ' ' ~ row['description'] ~ ': ' ~ count ~ pct) }}
    {% if row['status'] in ['missing', 'low'] and row['guide_section'] not in ns.next %}{% set ns.next = ns.next + [row['guide_section']] %}{% endif %}
  {% endfor %}
  {% if ns.next %}
    {{ print('') }}
    {{ print('Next steps:') }}
    {% for section in ns.next %}{{ print('  → ' ~ section) }}{% endfor %}
  {% endif %}
{% endmacro %}
