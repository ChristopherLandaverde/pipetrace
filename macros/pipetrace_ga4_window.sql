{% macro pipetrace_ga4_start_date() -%}
  {% if var('ga4_start_date', none) is not none %}
    date('{{ var("ga4_start_date") }}')
  {% else %}
    date_sub(current_date('{{ var("ga4_timezone") }}'), interval {{ var('ga4_lookback_days') | int }} day)
  {% endif %}
{%- endmacro %}
{% macro pipetrace_ga4_end_date() -%}
  {% if var('ga4_end_date', none) is not none %}
    date('{{ var("ga4_end_date") }}')
  {% else %}
    date_sub(current_date('{{ var("ga4_timezone") }}'), interval 1 day)
  {% endif %}
{%- endmacro %}
