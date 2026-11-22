# Setup guide

`Setup guide · Nov 2026 · From a first build to session-level attribution · Read-only on GA4, HubSpot and Salesforce`

PipeTrace credits each opportunity at the strongest level its data supports. The first build works with what you already have (level 0). Each later level adds one piece of instrumentation, and `pipetrace_doctor` tells you which piece is missing.

```
□ OBSERVED   Your GA4 export, HubSpot contacts, Salesforce leads and opportunities
↓ TRACED     pipetrace_doctor counts the deals each level reaches
+ REPAIRED   Add the one field the next level needs
✓ VERIFIED   Rebuild; the doctor shows deals moving up a level
```

| Level | `attribution_basis` | What you add | What you get |
|---|---|---|---|
| 0 | `crm_source` | Nothing | Channel credit from the source the CRM recorded, reconciled to deal value |
| 1 | `ga_client_id` | One hidden form field | Credit across every GA4 session of the buyer's browser before the deal |
| 2 | `conversion_token` | A token on the conversion event and the form | The strictest trace: the exact sessions that held the conversion |

Levels never mix within a deal, so first-observed and linear credit each sum to 1 per opportunity at any level.

## Before you start

1. **GA4 BigQuery export.** Daily export (`events_YYYYMMDD`) turned on for one property. Intraday tables are ignored.
2. **CRM tables in BigQuery.** HubSpot contacts and Salesforce leads and opportunities, loaded by Fivetran, Airbyte, or anything that matches the [source contract](source-contracts.md). Set `pipetrace_connector` to `native`, `fivetran` or `airbyte`.
3. **One BigQuery location** for every source dataset and the output dataset.
4. **HubSpot linked to Salesforce.** PipeTrace follows record IDs, never email. A HubSpot contact only reaches an opportunity through its Salesforce lead or contact ID (`property_salesforceleadid`, `property_salesforcecontactid`), which the HubSpot–Salesforce integration writes. Without HubSpot, Salesforce alone works: leads and opportunities carry their own fields.

Then build and read the report:

```bash
dbt build --vars '{ga4_dataset: analytics_123456789, hubspot_dataset: hubspot, salesforce_dataset: salesforce, ga4_timezone: America/New_York, pipetrace_connector: fivetran}'
dbt run-operation pipetrace_doctor
```

If `GA4 sessions found in the observation window` is 0, stop there: the dataset name, the date window (`ga4_lookback_days`, or `ga4_start_date` and `ga4_end_date`) or the timezone is wrong. Every opportunity would otherwise fall to level 0 and look like a CRM-source result instead of a coverage gap.

## Level 0: CRM source

Nothing to install. PipeTrace reads the source each CRM already records:

- **Salesforce leads:** first-touch source, medium and campaign fields. Point the vars at the fields your org already has. The defaults are `First_Touch_Source__c`, `First_Touch_Medium__c` and `First_Touch_Campaign__c`. Medium values go through the same channel rules as GA4 (`cpc` → Paid Search, `email` → Email, `organic` → Organic Search).
- **HubSpot contacts:** Original Source (`hs_analytics_source`), which HubSpot's tracking code fills in on its own. `PAID_SEARCH`, `ORGANIC_SEARCH`, `EMAIL_MARKETING`, `SOCIAL_MEDIA`, `PAID_SOCIAL`, `REFERRALS` and `DIRECT_TRAFFIC` map to the matching channels.

```yaml
vars:
  pipetrace:
    sfdc_lead_first_touch_source_field: UTM_Source__c
    sfdc_lead_first_touch_medium_field: UTM_Medium__c
    sfdc_lead_first_touch_campaign_field: UTM_Campaign__c
```

Field names are case-sensitive and must match the column exactly as BigQuery stores it. A field that does not exist reads as NULL instead of failing the build, so check the doctor: `Salesforce leads with first-touch source or medium` at 0% means the var points at nothing.

Limits:
- Only a CRM record created on or before the opportunity counts. A source written after the deal opened is ignored.
- Level 0 is the CRM's claim about a channel, not a traced session. Report it apart from levels 1 and 2. Both attribution marts keep `attribution_basis` for that.
- Salesforce first-touch fields rank above HubSpot's Original Source when both exist.

Turn level 0 off with `enable_crm_source_fallback: false`. Deals without session evidence then stay Unattributed.

## Level 1: GA4 client ID

GA4 identifies a browser by its client ID, stored in the `_ga` cookie as `GA1.1.1234567890.1700000000`. The export calls the last two parts `user_pseudo_id`. Store the cookie value on the CRM record when the form is submitted, and PipeTrace credits every GA4 session from that browser in the lookback window before the opportunity was created.

### 1. Create the field

- **HubSpot:** a contact property, single-line text, internal name `ga_client_id`. Fivetran and Airbyte land it as `property_ga_client_id`, the default for `hubspot_ga_client_id_property`.
- **Salesforce (optional):** a Lead text field `GA_Client_ID__c`. If you use HubSpot, map the HubSpot property to it in the HubSpot–Salesforce integration. HubSpot alone is enough when its contacts are linked to Salesforce.

### 2. Add a hidden field to every form that creates leads

In HubSpot, add the `ga_client_id` property to the form as a hidden field. For a non-HubSpot form, add `<input type="hidden" name="ga_client_id">` and send it to the same property.

### 3. Fill it from the cookie in Google Tag Manager

A Custom HTML tag that fires on every page with a form:

```html
<script>
(function () {
  var match = document.cookie.match(/(?:^|; )_ga=([^;]*)/);
  if (!match) return;
  var clientId = decodeURIComponent(match[1]);
  function fill() {
    document.querySelectorAll('input[name="ga_client_id"]').forEach(function (input) {
      if (input.value) return;
      input.value = clientId;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }
  fill();
  // Forms that render after the page loads.
  new MutationObserver(fill).observe(document.documentElement, { childList: true, subtree: true });
})();
</script>
```

If a form renders inside an iframe, a script on the parent page cannot reach it. Use the form tool's own hidden-field prefill instead (for example a URL parameter or its JavaScript API).

PipeTrace strips the `GA1.1.` prefix itself, so store the raw cookie value. Do not use a `_ga_<container>` cookie: that is the session cookie, not the client ID.

### 4. Verify

Submit a test form, wait for the CRM sync and the next daily GA4 export, then rebuild:

- `HubSpot contacts with a GA4 client ID` (or the Salesforce line) rises above 0%.
- `CRM GA4 client IDs that appear in GA4 as user_pseudo_id` stays near 100%. A low share means the stored value is not the `_ga` cookie, or the browser had no analytics consent.

Limits:
- A client ID is one browser on one device. A buyer seen on a phone and a laptop is credited across both only if both IDs reach the CRM.
- `_ga` exists only after analytics consent. Visitors who decline are not matched, by design.
- Safari limits cookies set by page scripts, so a returning Safari visitor can carry a new client ID. A first-party cookie set from your server (server-side tagging) keeps the ID stable.

Turn level 1 off with `enable_ga_client_id_matching: false`.

## Level 2: conversion token

A conversion token is a random ID created at the moment of conversion. It is sent to GA4 on the conversion event and written to the CRM in the same submission. PipeTrace then credits exactly the sessions that held the conversion, and nothing else. A token must be opaque: never an email address, a phone number or any other personal data.

### 1. Create the fields

- **HubSpot:** contact property `original_conversion_id` (single-line text). Lands as `property_original_conversion_id`.
- **Salesforce:** Lead field `Original_Conversion_Id__c` and Opportunity field `Original_Conversion_Id__c`. In Salesforce's lead conversion settings, map the Lead field to the Opportunity field so the token survives conversion.
- Map the HubSpot property to the Salesforce Lead field in the HubSpot–Salesforce integration.

### 2. Generate the token, fill the form, send the event

Add `original_conversion_id` to the form as a hidden field, then in GTM:

```html
<script>
(function () {
  var token = (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
    : 'pt-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
  function fill() {
    document.querySelectorAll('input[name="original_conversion_id"]').forEach(function (input) {
      if (input.value) return;
      input.value = token;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }
  fill();
  new MutationObserver(fill).observe(document.documentElement, { childList: true, subtree: true });
  window.pipetraceConversionId = token;
})();
</script>
```

On the form's successful submission, push the same token with the conversion event:

```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({ event: 'generate_lead', original_conversion_id: window.pipetraceConversionId });
```

Then add a GA4 event tag for `generate_lead` with an event parameter `original_conversion_id` set to a Data Layer Variable of the same name. The BigQuery export includes every event parameter, so no custom dimension is needed. If your parameter has another name, set `ga4_conversion_token_param`. Add the event name to `lead_conversion_events` if it is not already one of `generate_lead`, `form_submit` or `demo_request`.

### 3. Verify

After a test submission, the next export and a rebuild:

- `GA4 sessions carrying a conversion token` rises above 0.
- `CRM conversion tokens that appear in GA4` stays near 100%. A low share means the event fired without the parameter, or the form and the event used different tokens.
- `assert_conversion_tokens_not_shared_across_users` passes. A token shared by two browsers fails the build, because it would credit one deal to two people.

## Reading the readiness check

`dbt run-operation pipetrace_doctor` prints the `pipetrace_readiness` table. Each line is one check:

| Mark | Status | Meaning |
|---|---|---|
| `✓` | `ok` | The field is populated, or deals reach this level |
| `!` | `low` | Under 50% of rows have the field |
| `×` | `missing` | 0% of rows have the field, or no GA4 sessions were found |
| `!` | `review` | Some deals have no evidence at any level (the Unattributed count) |
| `·` | `no_rows` | The table has no rows to check |
| `-` | `off` | The level is turned off by a var |

The `MATCH` section is the one to watch after a change: it compares the values stored in the CRM with what GA4 actually exported. A field can be 100% populated and still match nothing when its format is wrong.

The report ends with the guide sections for each `missing` or `low` line. Work from level 0 up: each level only adds deals that the one below could not credit.

Field notes on this problem ↗ [focosys.io](https://focosys.io) · Start with the decision you cannot trust: [christopher@focosys.io](mailto:christopher@focosys.io)
