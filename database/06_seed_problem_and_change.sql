-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/06_seed_problem_and_change.sql
-- Description: Direct Seed script for Problem (PRB-2026-001) & Change (CHG-2026-042)
-- Author: Mahi Zaman
-- ============================================================================

-- 1. Create Problem Record for Top Recurring Issue (FR-12, FR-13)
MERGE INTO PROBLEMS p
USING (SELECT 'PRB-2026-001' AS PROBLEM_ID FROM DUAL) src
ON (p.PROBLEM_ID = src.PROBLEM_ID)
WHEN MATCHED THEN
    UPDATE SET 
        TITLE = 'Recurring Payment Gateway Timeout due to Connection Pool Starvation',
        CATEGORY = 'SOFTWARE',
        SERVICE = 'PAYMENT_GATEWAY',
        ROOT_CAUSE = 'Connection Pool Exhaustion under Peak Traffic',
        RCA_5_WHYS = 'Why 1: Payment processing API requests intermittently returned HTTP 504 Gateway Timeout during peak traffic.
Why 2: Worker threads in the Payment Gateway microservice were stalled waiting for JDBC connections from the pool.
Why 3: The maximum HikariCP database connection pool size was statically capped at 20 connections, while concurrent payment requests exceeded 140.
Why 4: Legacy merchant webhook notification logic retained database connections across slow synchronous outbound HTTP calls without a timeout guard.
Why 5: Lack of automated connection pool saturation alerting and missing architectural standard separating asynchronous webhook dispatches from transactional database sessions.',
        KNOWN_ERROR_FLAG = 1,
        WORKAROUND = '1. Rolling Restart: Execute rolling restart of Payment Gateway pods (kubectl rollout restart deployment/payment-gateway-service).
2. Dynamic Pool Scaling: Update maximum pool size to 60 via Spring Cloud Config dynamic refresh endpoint.
3. Circuit Breaker: Enable fallback queue for asynchronous webhook notifications to release thread holds immediately.',
        STATUS = 'CHANGE_PENDING'
WHEN NOT MATCHED THEN
    INSERT (
        PROBLEM_ID, TITLE, CATEGORY, SERVICE, ROOT_CAUSE, 
        RCA_5_WHYS, KNOWN_ERROR_FLAG, WORKAROUND, STATUS, CREATED_DATE
    ) VALUES (
        'PRB-2026-001',
        'Recurring Payment Gateway Timeout due to Connection Pool Starvation',
        'SOFTWARE',
        'PAYMENT_GATEWAY',
        'Connection Pool Exhaustion under Peak Traffic',
        'Why 1: Payment processing API requests intermittently returned HTTP 504 Gateway Timeout during peak traffic.
Why 2: Worker threads in the Payment Gateway microservice were stalled waiting for JDBC connections from the pool.
Why 3: The maximum HikariCP database connection pool size was statically capped at 20 connections, while concurrent payment requests exceeded 140.
Why 4: Legacy merchant webhook notification logic retained database connections across slow synchronous outbound HTTP calls without a timeout guard.
Why 5: Lack of automated connection pool saturation alerting and missing architectural standard separating asynchronous webhook dispatches from transactional database sessions.',
        1,
        '1. Rolling Restart: Execute rolling restart of Payment Gateway pods (kubectl rollout restart deployment/payment-gateway-service).
2. Dynamic Pool Scaling: Update maximum pool size to 60 via Spring Cloud Config dynamic refresh endpoint.
3. Circuit Breaker: Enable fallback queue for asynchronous webhook notifications to release thread holds immediately.',
        'CHANGE_PENDING',
        TIMESTAMP '2026-11-01 09:30:00'
    );

-- 2. Link all matching recurring incidents to PRB-2026-001 (FR-12)
INSERT INTO INCIDENT_PROBLEM_LINK (TICKET_ID, PROBLEM_ID)
SELECT i.TICKET_ID, 'PRB-2026-001'
FROM INCIDENTS i
WHERE i.CATEGORY = 'SOFTWARE'
  AND i.SERVICE = 'PAYMENT_GATEWAY'
  AND i.ROOT_CAUSE = 'Connection Pool Exhaustion under Peak Traffic'
  AND NOT EXISTS (
      SELECT 1 FROM INCIDENT_PROBLEM_LINK l
      WHERE l.TICKET_ID = i.TICKET_ID AND l.PROBLEM_ID = 'PRB-2026-001'
  );

-- 3. Create Change Request record (FR-14)
MERGE INTO CHANGES c
USING (SELECT 'CHG-2026-042' AS CHANGE_ID FROM DUAL) src
ON (c.CHANGE_ID = src.CHANGE_ID)
WHEN MATCHED THEN
    UPDATE SET 
        TITLE = 'Payment Gateway Asynchronous Connection & Pool Hardening',
        DESCRIPTION = '1. Decouple merchant webhook dispatch into an event-driven Kafka queue, releasing DB connections prior to outbound HTTP calls.
2. Reconfigure HikariCP pool size from 20 to 80 with connectionTimeout=3000ms, idleTimeout=60000ms, maxLifetime=1800000ms.
3. Implement Prometheus HikariCP metrics and Alertmanager trigger at 80% pool utilization for 2 consecutive minutes.',
        RISK_LEVEL = 'MEDIUM',
        IMPACT_LEVEL = 'HIGH',
        TEST_PLAN = '1. Pre-Deployment Staging Load Test: Simulate 350 TPS concurrent payment requests for 45 minutes; verify 0 connection timeouts.
2. Fault Injection Test: Introduce 10-second latency on external webhook endpoint; verify DB connections release immediately.
3. Canary Verification: Deploy to Canary pod (10% traffic) for 2 hours monitoring HTTP error rates and DB active connections.',
        BACKOUT_PLAN = '1. Rollback Trigger Criteria: Error rate > 0.5% or P99 response time > 800ms sustained over 3 minutes.
2. Rollback Execution: Revert Helm deployment release to image v2.4.1 (helm rollback payment-gateway-svc <prior-revision>).
3. Rollback Timeframe: Automated rollback executes in < 4 minutes with 0 scheduled downtime.',
        APPROVAL_STATUS = 'APPROVED',
        APPROVED_BY = 'CAB Chair (Elena Rostova)',
        APPROVAL_DATE = TIMESTAMP '2026-11-10 16:00:00',
        IMPLEMENTATION_STATUS = 'SUCCESSFUL'
WHEN NOT MATCHED THEN
    INSERT (
        CHANGE_ID, PROBLEM_ID, CHANGE_TYPE, TITLE, DESCRIPTION,
        RISK_LEVEL, IMPACT_LEVEL, TEST_PLAN, BACKOUT_PLAN,
        APPROVAL_STATUS, APPROVED_BY, APPROVAL_DATE, SCHEDULED_START, SCHEDULED_END, IMPLEMENTATION_STATUS
    ) VALUES (
        'CHG-2026-042',
        'PRB-2026-001',
        'NORMAL',
        'Payment Gateway Asynchronous Connection & Pool Hardening',
        '1. Decouple merchant webhook dispatch into an event-driven Kafka queue, releasing DB connections prior to outbound HTTP calls.
2. Reconfigure HikariCP pool size from 20 to 80 with connectionTimeout=3000ms, idleTimeout=60000ms, maxLifetime=1800000ms.
3. Implement Prometheus HikariCP metrics and Alertmanager trigger at 80% pool utilization for 2 consecutive minutes.',
        'MEDIUM',
        'HIGH',
        '1. Pre-Deployment Staging Load Test: Simulate 350 TPS concurrent payment requests for 45 minutes; verify 0 connection timeouts.
2. Fault Injection Test: Introduce 10-second latency on external webhook endpoint; verify DB connections release immediately.
3. Canary Verification: Deploy to Canary pod (10% traffic) for 2 hours monitoring HTTP error rates and DB active connections.',
        '1. Rollback Trigger Criteria: Error rate > 0.5% or P99 response time > 800ms sustained over 3 minutes.
2. Rollback Execution: Revert Helm deployment release to image v2.4.1 (helm rollback payment-gateway-svc <prior-revision>).
3. Rollback Timeframe: Automated rollback executes in < 4 minutes with 0 scheduled downtime.',
        'APPROVED',
        'CAB Chair (Elena Rostova)',
        TIMESTAMP '2026-11-10 16:00:00',
        TIMESTAMP '2026-11-12 02:00:00',
        TIMESTAMP '2026-11-12 03:30:00',
        'SUCCESSFUL'
    );

COMMIT;

-- Verification output
PROMPT Problem and Change records seeded successfully.
SELECT p.PROBLEM_ID, p.TITLE, COUNT(l.TICKET_ID) AS LINKED_INCIDENTS, p.STATUS
FROM PROBLEMS p
LEFT JOIN INCIDENT_PROBLEM_LINK l ON p.PROBLEM_ID = l.PROBLEM_ID
GROUP BY p.PROBLEM_ID, p.TITLE, p.STATUS;

SELECT CHANGE_ID, PROBLEM_ID, TITLE, APPROVAL_STATUS, IMPLEMENTATION_STATUS
FROM CHANGES;
