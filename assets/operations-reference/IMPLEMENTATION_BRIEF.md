# Headquarters — Operations dashboard redesign

## Objective
Implement a production-quality redesign of the existing iOS Headquarters app. It is the personal mission-control centre for the entire ecosystem: show what is running, who or what runs it, how systems exchange information, where a failure occurred, and what action is needed. Simple first, deep on tap. Implement in the existing repository; do not merely return recommendations or a plan.

## 1. Inspect before editing
Inspect the existing SwiftUI architecture, navigation, themes, asset catalog, data sources, persistence, monitoring, tests, build configuration and any existing integration contracts. Preserve working functionality, app identity, signing, launch animation, user data and settings. Reuse existing components when suitable. Identify actual repositories and services from verified configuration; inspect sibling repositories only where access is available. Do not infer that a planned automation or integration is deployed. Avoid unrelated rewrites or modifications to sibling apps without identifying the dependency and reporting the required changes. Never expose secrets in source, logs or UI.

## 2. Visual reference and assets
`references/Approved_Mockup.png` is the approved visual reference for the Headquarters systems page and selected Daily Briefing operations page. The other seven PNGs are original brand references. Use existing exact square app-icon assets if available. Otherwise use the supplied art with careful square framing, preserving the actual motif, proportions and colours; never replace it with generic SF Symbols or redraw it. The portrait references are artwork, not ready-made square icon files. Avoid hard letterbox edges, distorted art or clipped subjects. Preserve the existing HQ subtle mountain landscape / blue-hour background while adopting the approved mockup's dark navy, graphite and translucent glass surfaces. Keep crisp readable typography, restrained highlights, realistic depth, consistent spacing, and clear hierarchy. Do not copy device frames, status-bar artwork, or illustrative text/metrics from the mockup into the UI. Use native safe areas, accessibility labels, Dynamic Type and Reduce Motion. Aim to fit the default main dashboard on an iPhone screen without vertical scrolling; adapt gracefully for larger accessibility text. Detail pages can scroll when necessary. No decorative charts or fabricated percentages.

## 3. HQ overview and systems
The home screen is a compact, customizable status board (preserve existing widget customization if present): overall ecosystem health, apps monitored, active jobs/agents, issues requiring attention and a compact activity summary. Use meaningful progress graphics with real denominators where available. The Systems screen follows the approved mockup: branded app icons, app name, one useful operational summary, status indicator, and a clear tap affordance. Include Daily Briefing, Logbook (fitness/nutrition, NOT aviation flight records), Stack (finance), Stocked (inventory), Crew (AI agents), YKF Tracker (flight tracking), and HQ's own health. Distinguish app availability from integration and development health. Existing navigation may be reused; suggested top-level sections are Overview, Systems, Activity, Alerts. Avoid redundant screens; tapping an app always opens its operations view inside HQ, not the actual app. Optional explicit Open App action only if a supported deep link exists.

## 4. App-specific appearance
Use one reusable operations layout with a per-app theme token/asset system. On selection, transition the entire operations screen into the chosen app's identity (background, surfaces, typography contrast, accent, icon, header and controls); restore HQ styling on back navigation. Prefer actual current themes from each app if available, with these references as fallbacks:
- Headquarters: midnight navy, blue glass, layered panels, subtle mountains.
- Daily Briefing: approved blue/white glass and flowing blue waves; match the selected-app mockup closely.
- Logbook: graphite/black, silver angular L, restrained metallic accents; respect the current app theme if discoverable.
- Stack: warm cream/champagne and gold, gold coins.
- Crew: warm cream and restrained colourful agent accents, five-character artwork.
- Stocked: cool silver/steel, pale blue-grey, subtle warm accents, refrigerator.
- YKF Tracker: dark navy, aviation radar, cool blue and silver, aircraft tail.
Keep status semantics consistent regardless of theme and ensure sufficient contrast in light/dark themes.

## 5. App operations screen
Use the right-hand approved mockup as the layout reference: back to HQ, app icon and title, compact summary (operational status, connected/expected integrations, missing count, last verified refresh), large simplified interaction map, recent activity and actionable issues. Provide deeper Overview / Map / Activity / Issues / Config sections as appropriate, without duplicating information or overcrowding the default view. Add a full-screen map option if needed. A tap on an icon/node or line must open a useful inspector. Use smooth transitions and minimal motion; pulses represent actual in-progress work, not decorative fake traffic.

## 6. Interaction graph
Represent real directed relationships, not a generic spider chart with every service connected directly to the app. Default to a simplified app-centred view; allow expansion into upstream inputs, processing/automation, storage, outputs and development/deployment. Group or collapse complex branches, show arrow direction, label the responsibility of each edge, support pan/zoom or expanded inspection where needed, and avoid crossings. Examples of actors: Apple Calendar, HealthKit, Reminders, weather provider, Gmail, FlightBridge, Grok agents, GitHub Actions, scheduled jobs, app backend, iCloud, local storage, widgets and notifications. These are candidates, not confirmed integrations. Show actual chains, e.g. source → scheduled automation → processor → app → notification, when verified. GitHub build/deployment paths must be separate from runtime data flows unless a real runtime dependency exists. Distinguish which bot, script, scheduler or service owns each step. For shared dependencies, show affected apps and downstream impact. Provide a system-wide graph in Systems if practical using the same graph model, with filters, rather than duplicating separate hardcoded maps.

Edge and node semantics:
- Green solid + check: verified healthy within its expected freshness window.
- Orange solid + warning: delayed/degraded/partial success; show reason.
- Red solid + X: verified failure; show failing stage.
- Grey dashed + broken-link or plus: expected, genuinely unconfigured/missing connection; label Missing and offer an appropriate setup action.
- Neutral grey + question mark: unknown/unverified/no telemetry. Distinct from missing.
- Muted paused state: intentionally disabled, not necessarily a fault.
- Subtle blue/white pulse overlay: confirmed active job/transfer, independent of underlying health.
Do not rely on colour alone. A failed upstream edge can mark downstream work blocked/stale without inventing a second failure. Do not infer healthy from app installation, repository existence, or a successful unrelated build. A GitHub failure does not necessarily mean the installed app is offline.

## 7. Inspectors and remediation
Node inspector: identity/type, role, owner, source, permissions/configuration, last check, last success, affected flows, relevant logs or evidence and appropriate setup/reconnect action.
Edge inspector: source → destination, operation, status, last attempt/success/failure, expected cadence, latency where measured, sanitized error, impact, retry/repair suggestion and responsible actor. Where safe and actually supported, allow recheck, retry, open relevant settings or link to GitHub run; confirm actions with side effects. Never display fake actionable buttons. For Apple Calendar missing, explain schedule impact and route to the relevant app's permission/setup workflow (HQ cannot grant another app's permissions). Distinguish missing credentials from denied permissions, rate limits, stale data, unreachable services and failed jobs. Record action results accurately.

## 8. Monitoring architecture and evidence
Create/reuse typed models for monitored systems, nodes, directed edges, expected integrations, health observations, jobs, incidents and activity events. Suggested fields: stable IDs, kind, owner, purpose, source/destination, expected cadence, status, observedAt, lastAttempt, lastSuccess, lastFailure, sanitized reason, evidence/source, impact, and supported actions. Build adapters around existing integrations and real telemetry. A dependency registry/manifest should describe expected connections separately from observations; compare the two to identify truly missing links. Cache last known observations with timestamps, mark stale/unknown appropriately, deduplicate events, and support refresh with loading/offline/error states. Aggregate app health based on criticality and impact; surface development, data sync, runtime and agent health separately. Do not report all systems operational when critical checks are unknown.

iOS sandbox/background execution constraints matter: HQ cannot directly inspect another app's private data, permissions or arbitrary processes. Prefer supported shared backend telemetry or explicitly implemented cross-app reporting; app groups/shared storage only when configured and suitable. Do not invent an always-on iOS polling service. GitHub/Grok integrations require supported APIs, authentication and real telemetry; do not scrape private chat or imply access to consumer Grok bot execution logs when unavailable. Respect existing backend and credential storage. If no integration is accessible, implement an honest unverified/setup state and document the exact adapter, permission, endpoint or sibling-app instrumentation required. Do not hardcode mock values as production data. Preview fixtures are allowed only in clearly marked previews/test/demo paths.

## 9. Candidate app maps to validate
- Daily Briefing: calendar/reminders, work schedules, email, weather, FlightBridge, Logbook habit data, briefing automation/agents, local presentation/widgets/notifications. Use actual sources and logic, not the mockup as an architecture manifest.
- Logbook: nutrition/training/check-ins, HealthKit, iCloud, watch companion, Live Activities, and any actual downstream habit reporting.
- Stack: actual bank import/transaction source, categorization, storage and finance automations; BMO automation is a goal, not evidence that it exists.
- Stocked: actual inventory source, storage, shopping or nutrition links only when supported.
- Crew: actual Grok agents, automation triggers, task execution, outputs and failures; identify individual agents when evidence exists.
- YKF Tracker: actual flight/ADS-B feeds, processing, alerts, refresh and cache.
- Headquarters: monitoring adapters, registry, backend/health collection, alerts and its own build/runtime state.
For all apps, GitHub repository/CI status belongs in a development branch of the map if connected. The list is not authorization to fabricate or connect external accounts.

## 10. Activity and alerts
Show chronological real events with timestamp, app, actor, action, outcome and relevant flow. Filter by app/severity and allow jumping to the exact node/edge. Prioritize actionable issues, distinguish unconfigured dependencies from operational incidents, consolidate shared root causes, show affected features and suggested repair. Preserve any existing notification preferences; avoid repeated alerts for the same unresolved event.

## 11. Implementation and acceptance
Implement incrementally: audit → shared themes/assets and screens → typed graph/inspectors → adapters and aggregation → tests and visual verification. Build the actual iOS target with available Xcode tooling. Test navigation, theme restoration, all six app themes plus HQ, node/edge inspection, missing vs unknown vs paused, degraded/failed/stale observations, partial refresh, downstream impact, offline states, accessibility, screen sizing and persistence. Verify on a standard iPhone 16-size simulator where available; use screenshots of the HQ Systems page and Daily Briefing plus at least one dark and one warm-themed detail page. Preserve launch experience and avoid regressions. If build/simulator access is unavailable, report the limitation rather than claiming success.

Final report: changes and files, what is genuinely connected/verified vs not configured vs unknown, required setup and cross-app changes, build/test results, screenshots if available, and commit/branch status. Do not claim completion of external integration work that remains blocked. Commit work according to the existing repository workflow; do not overwrite unrelated changes or force-push. 
