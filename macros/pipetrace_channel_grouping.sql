{#- Small, transparent channel rules shared by GA4 sessions and CRM first-touch
    fields. Arguments are SQL expressions. Kept to plain CASE so the local
    SQLite acceptance tests can expand it. -#}
{% macro pipetrace_channel_grouping(source, medium) -%}
  case
    when lower({{ medium }}) in ('paid_social', 'paidsocial') then 'Paid Social'
    when lower({{ medium }}) in ('cpc', 'ppc', 'paidsearch') then 'Paid Search'
    when lower({{ medium }}) in ('email', 'newsletter') then 'Email'
    when lower({{ medium }}) = 'organic' then 'Organic Search'
    when lower({{ medium }}) = 'referral' then 'Referral'
    when lower({{ medium }}) = 'social' then 'Organic Social'
    when ({{ source }} is null or {{ source }} = '(direct)')
      and ({{ medium }} is null or {{ medium }} in ('(none)', '(not set)')) then 'Direct'
    else 'Unassigned'
  end
{%- endmacro %}

{#- HubSpot's hs_analytics_source enum, mapped onto the same channel names. -#}
{% macro pipetrace_hubspot_source_channel(source) -%}
  case upper({{ source }})
    when 'ORGANIC_SEARCH' then 'Organic Search'
    when 'PAID_SEARCH' then 'Paid Search'
    when 'EMAIL_MARKETING' then 'Email'
    when 'SOCIAL_MEDIA' then 'Organic Social'
    when 'PAID_SOCIAL' then 'Paid Social'
    when 'REFERRALS' then 'Referral'
    when 'AI_REFERRALS' then 'Referral'
    when 'DIRECT_TRAFFIC' then 'Direct'
    when 'OFFLINE' then 'Offline'
    else 'Unassigned'
  end
{%- endmacro %}

{#- Read a column that may not exist in the source table. Returns a trimmed
    STRING, or NULL when the column is absent or blank. -#}
{% macro pipetrace_optional_column(column_name, row_json='row_json') -%}
  {%- if column_name is none or column_name == '' -%}
    cast(null as string)
  {%- else -%}
    nullif(trim(json_value({{ row_json }}, '$.{{ column_name | replace("'", "") }}')), '')
  {%- endif -%}
{%- endmacro %}

{#- GA4 client IDs captured from the _ga cookie look like GA1.1.123.456;
    the export's user_pseudo_id is the 123.456 part. -#}
{% macro pipetrace_normalize_ga_client_id(expression) -%}
  nullif(regexp_replace(trim({{ expression }}), r'^GA\d+\.\d+\.', ''), '')
{%- endmacro %}
