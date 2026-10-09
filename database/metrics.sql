-- SwiftDrop Logistics: operational metrics
-- Run with: docker exec swiftdrop-postgres psql -U swiftdrop -d swiftdrop -f /dev/stdin < database/metrics.sql
-- or paste individual queries into psql for the demo video.

-- 1. Total requests (new conversations started, one per customer-initiated intent)
SELECT COUNT(*) AS total_requests
FROM audit_logs
WHERE event_type = 'INTENT_CLASSIFIED'
  AND (details->>'continued_conversation')::boolean = false;

-- 2. Intent breakdown
SELECT
  details->>'intent' AS intent,
  COUNT(*) AS request_count
FROM audit_logs
WHERE event_type = 'INTENT_CLASSIFIED'
  AND (details->>'continued_conversation')::boolean = false
GROUP BY details->>'intent'
ORDER BY request_count DESC;

-- 3. Escalations: total, by priority, by status
SELECT priority, status, COUNT(*) AS count
FROM escalations
GROUP BY priority, status
ORDER BY priority, status;

-- 4. Unresolved escalations (needs human follow-up right now)
SELECT COUNT(*) AS unresolved_escalations
FROM escalations
WHERE status <> 'RESOLVED';

-- 5. Integration failures (simulated tracking-service outages)
SELECT COUNT(*) AS integration_failures
FROM audit_logs
WHERE event_type = 'INTEGRATION_FAILURE';

-- 6. Automation success rate: of conversations that reached a terminal state,
--    what percentage completed fully automated (never escalated to a human)?
SELECT
  COUNT(*) FILTER (WHERE current_state = 'COMPLETED') AS completed,
  COUNT(*) FILTER (WHERE current_state = 'HUMAN_ESCALATION') AS escalated,
  COUNT(*) FILTER (WHERE current_state IN ('COMPLETED', 'HUMAN_ESCALATION')) AS terminal_total,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE current_state = 'COMPLETED')
    / NULLIF(COUNT(*) FILTER (WHERE current_state IN ('COMPLETED', 'HUMAN_ESCALATION')), 0),
    1
  ) AS automation_success_rate_pct
FROM conversations;

-- 7. Everything in one summary row (handy for the demo video / written submission)
SELECT
  (SELECT COUNT(*) FROM audit_logs WHERE event_type = 'INTENT_CLASSIFIED' AND (details->>'continued_conversation')::boolean = false) AS total_requests,
  (SELECT COUNT(*) FROM escalations) AS total_escalations,
  (SELECT COUNT(*) FROM escalations WHERE status <> 'RESOLVED') AS unresolved_escalations,
  (SELECT COUNT(*) FROM audit_logs WHERE event_type = 'INTEGRATION_FAILURE') AS integration_failures,
  (SELECT ROUND(
    100.0 * COUNT(*) FILTER (WHERE current_state = 'COMPLETED')
    / NULLIF(COUNT(*) FILTER (WHERE current_state IN ('COMPLETED', 'HUMAN_ESCALATION')), 0), 1)
   FROM conversations) AS automation_success_rate_pct;
