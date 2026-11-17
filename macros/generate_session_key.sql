{% macro generate_session_key(user_expression='user_pseudo_id', session_expression=none) -%}
  {% set sid = session_expression if session_expression is not none else extract_event_param('ga_session_id', 'int') %}
  case when nullif(trim({{ user_expression }}), '') is not null and {{ sid }} is not null
    then concat({{ user_expression }}, '-', cast({{ sid }} as string)) end
{%- endmacro %}
