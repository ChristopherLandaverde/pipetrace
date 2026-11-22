with cases as (
  select [struct('token' as key, struct(cast(null as string) as string_value,
      123 as int_value, cast(null as float64) as double_value, cast(null as float64) as float_value) as value)] as event_params,
    '123' as expected_string, 123 as expected_int
  union all
  select [struct('token', struct('invalid', cast(null as int64), cast(null as float64), cast(null as float64)))], 'invalid', null
  union all
  select [struct('token', struct(cast(null as string), cast(null as int64), 4.5, cast(null as float64)))], '4.5', null
)
select * from cases
where {{ pipetrace_extract_event_param('token') }} is distinct from expected_string
   or {{ pipetrace_extract_event_param('token', 'int') }} is distinct from expected_int
