{#- Which loader produced the CRM tables: native (the source contract),
    fivetran, or airbyte. Set the pipetrace_connector var. -#}
{% macro pipetrace_connector() -%}
  {%- set c = var('pipetrace_connector', 'native') | lower -%}
  {%- if c not in ['native', 'fivetran', 'airbyte'] -%}
    {{ exceptions.raise_compiler_error('PipeTrace: pipetrace_connector must be native, fivetran or airbyte, not "' ~ c ~ '"') }}
  {%- endif -%}
  {{ return(c) }}
{%- endmacro %}

{#- The relation a staging model reads: the raw source table, or the
    connector mapping view that reshapes it into the source contract. -#}
{% macro pipetrace_crm_relation(source_name, table_name) -%}
  {%- set mapped = {
    'fivetran': ['hubspot.contacts', 'salesforce.leads', 'salesforce.opportunities'],
    'airbyte': ['hubspot.contacts'],
  } -%}
  {%- set c = pipetrace_connector() -%}
  {%- if (source_name ~ '.' ~ table_name) in mapped.get(c, []) -%}
    {{ return(ref('pipetrace_' ~ c ~ '__' ~ source_name ~ '_' ~ table_name)) }}
  {%- else -%}
    {{ return(source(source_name, table_name)) }}
  {%- endif -%}
{%- endmacro %}

{#- Fivetran's column naming for a Salesforce API name:
    GA_Client_ID__c -> ga_client_id_c, ConvertedOpportunityId -> converted_opportunity_id -#}
{% macro pipetrace_fivetran_name(name) -%}
  {%- set s = modules.re.sub('([a-z0-9])([A-Z])', '\\1_\\2', name) | lower -%}
  {{ return(modules.re.sub('_+', '_', s).strip('_')) }}
{%- endmacro %}

{#- HubSpot internal property name from a property_* column name. -#}
{% macro pipetrace_hubspot_property_name(column_name) -%}
  {{ return(column_name[9:] if column_name.startswith('property_') else column_name) }}
{%- endmacro %}

{% macro pipetrace_hubspot_contact_columns() -%}
  {{ return(['property_email', 'property_hs_analytics_source', 'property_hs_analytics_source_data_1',
             'property_hs_lead_status', 'property_salesforceleadid', 'property_salesforcecontactid',
             var('hubspot_conversion_token_property'), var('hubspot_ga_client_id_property')]) }}
{%- endmacro %}

{% macro pipetrace_sfdc_custom_fields(object_name) -%}
  {%- if object_name == 'lead' -%}
    {{ return([var('sfdc_lead_first_touch_source_field'), var('sfdc_lead_first_touch_medium_field'),
               var('sfdc_lead_first_touch_campaign_field'), var('sfdc_lead_conversion_token_field'),
               var('sfdc_lead_ga_client_id_field')] | unique | list) }}
  {%- else -%}
    {{ return(['ARR__c', 'ContactId', 'CurrencyIsoCode', var('sfdc_opportunity_conversion_token_field'),
               var('sfdc_opportunity_ga_client_id_field')] | unique | list) }}
  {%- endif -%}
{%- endmacro %}
