{% macro extract_event_param(param_key, data_type='string', params='event_params') -%}
  {% if data_type not in ['string', 'int', 'double'] %}
    {{ exceptions.raise_compiler_error('extract_event_param: unsupported type ' ~ data_type) }}
  {% endif %}
  (select
    {% if data_type == 'string' %}
      coalesce(ep.value.string_value, cast(ep.value.int_value as string),
               cast(ep.value.double_value as string), cast(ep.value.float_value as string))
    {% elif data_type == 'int' %}
      coalesce(ep.value.int_value, safe_cast(ep.value.string_value as int64),
        if(coalesce(ep.value.double_value, ep.value.float_value) =
           trunc(coalesce(ep.value.double_value, ep.value.float_value)),
           safe_cast(coalesce(ep.value.double_value, ep.value.float_value) as int64), null))
    {% else %}
      coalesce(ep.value.double_value, ep.value.float_value, cast(ep.value.int_value as float64),
               safe_cast(ep.value.string_value as float64))
    {% endif %}
   from unnest({{ params }}) as ep with offset as param_offset
   where ep.key = '{{ param_key | replace("'", "''") }}'
   order by param_offset limit 1)
{%- endmacro %}
