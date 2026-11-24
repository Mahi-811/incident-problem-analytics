# ITIL Change Request: CHG-2026-042

**Change Title:** Payment Gateway Asynchronous Connection & Pool Hardening  
**Document Ref:** CHG-2026-042  
**Parent Problem Record:** [PRB-2026-001](PROBLEM_RECORD_PRB-2026-001.md)  
**Requester:** Mahi Zaman (Service Delivery Lead)  
**Lead Implementer:** David Chen (Application Engineering Lead)  
**Database Peer:** Elena Rostova (Lead Oracle DBA)  
**Change Type:** Normal (Requires Formal CAB Approval)  
**Implementation Window:** 12 Nov 2026, 02:00:00 UTC – 03:30:00 UTC (90 mins)  
**Service Outage:** Zero Scheduled Downtime (Rolling Blue/Green Deployment)  
**Status:** **Approved & Successfully Implemented**

---

## 1. Description of Change (FR-14)

This change implements the permanent architectural remediation for **PRB-2026-001** (recurring database connection pool starvation under high transaction volume):

1. **Decouple Merchant Callbacks via Event-Driven Queue:**
   - Remove synchronous HTTP POST client calls from within `@Transactional` boundary in `PaymentProcessingService.java`.
   - Publish payment confirmation events onto Apache Kafka topic `payment.merchant-notifications.v1`.
   - A dedicated asynchronous worker consumer group (`merchant-notifier-worker`) processes outbound HTTP calls with exponential backoff and dead-letter queue (DLQ) retry logic.

2. **Re-tune HikariCP Datasource Parameters:**
   - Expand `maximum-pool-size` from 20 to 80 connections per container instance.
   - Adjust `minimum-idle` to 20 connections.
   - Set `connection-timeout` to 3,000 ms (fail-fast rather than thread blocking).
   - Configure `leak-detection-threshold` to 2,000 ms to proactively log runaway query sessions.

3. **Database Listener & Sizing Adjustments (Oracle XE 21c):**
   - Verified Oracle database `processes` initialization parameter set to 400 (`ALTER SYSTEM SET processes=400 SCOPE=SPFILE`).

4. **Telemetry & Real-Time Alerting:**
   - Export Micrometer HikariCP metrics (`hikaricp_connections_active`, `hikaricp_connections_pending`) to Prometheus.
   - Configure Grafana alert rule: Trigger warning when pool saturation > 75% for 60 seconds; trigger P1 pager when pending threads > 10.

---

## 2. Risk and Impact Assessment (FR-14)

### 2.1 Risk Level: **Medium**
- **Risk 1: Database Resource Contention:** Increasing pool size to 80 per pod across 3 pods (up to 240 concurrent connections) could strain Oracle memory (SGA/PGA).  
  *Mitigation:* SGA allocated 4GB; peak memory load tested at 1.8GB during 500 TPS stress runs.
- **Risk 2: Out-of-Order Webhook Delivery:** Asynchronous processing might deliver notifications out of strict chronological order.  
  *Mitigation:* Kafka partition key set to `merchant_id` + `transaction_id`, guaranteeing per-merchant sequence ordering.

### 2.2 Impact Level: **High**
- **Affected Systems:** Payment Processing Service, Merchant Notification API, Oracle XE DB.
- **Customer Impact:** Positive. Eliminates payment timeouts; expected reduction in payment failure rate from 1.8% to < 0.01%.

---

## 3. Test and Validation Plan (FR-14)

The change underwent exhaustive multi-stage verification prior to CAB presentation:

| Test Stage | Test Description | Success Criteria | Result |
|:---|:---|:---|:---:|
| **Stage 1: Unit & Mock Tests** | 142 JUnit 5 test cases validating transaction boundaries and Kafka event emission. | 100% pass; 0 connection holds outside DB scope. | **PASS** |
| **Stage 2: Staging Load Test** | Simulated 500 TPS sustained load for 60 minutes with JMeter against staging cluster. | 0 connection timeouts; P99 response time < 140ms. | **PASS** |
| **Stage 3: Fault Injection** | Injected 10,000ms latency on external mock merchant callback endpoint. | DB connections released in < 18ms; worker pool handled retries cleanly. | **PASS** |
| **Stage 4: DB Session Audit** | Monitored `V$SESSION` and `V$ACTIVE_SESSION_HISTORY` during peak test loads. | 0 database deadlock conditions; active sessions stayed within safe limits. | **PASS** |

---

## 4. Implementation Steps & Maintenance Window

- **02:00 UTC:** Implementation bridge opens with Service Delivery, SRE, and DBA on call.
- **02:05 UTC:** Create pre-deployment configuration backup (`helm get values payment-gateway-svc > backup_v2.4.1.yaml`).
- **02:10 UTC:** Deploy Kafka topic provisioning and consumer deployment (`helm upgrade --install merchant-worker ./helm/merchant-worker`).
- **02:20 UTC:** Deploy updated Payment Gateway image `v2.5.0` via Kubernetes canary rollout (1 pod out of 3 updated).
- **02:35 UTC:** Canary validation: Run synthetic payment transactions; verify metrics in Grafana.
- **02:45 UTC:** Full rollout to remaining 2 pods (`kubectl rollout status deployment/payment-gateway-service`).
- **03:00 UTC:** Post-deployment smoke tests executed by QA and Incident Desk.
- **03:15 UTC:** Sign-off and bridge closure.

---

## 5. Back-out & Rollback Plan (FR-14)

### 5.1 Rollback Trigger Criteria
The implementation lead must trigger immediate rollback if any of the following occur:
1. `HTTP 5xx` error rate exceeds 0.5% sustained over 3 consecutive minutes.
2. Payment API P99 latency exceeds 800ms.
3. Oracle database reports ORA-00018 (maximum number of sessions exceeded).

### 5.2 Rollback Procedure (< 4 Minutes Execution Time)
```bash
# 1. Rollback Payment Gateway Kubernetes deployment to previous revision v2.4.1
helm rollback payment-gateway-svc 14 -n payments

# 2. Scale down asynchronous consumer pods
kubectl scale deployment/merchant-notifier-worker --replicas=0 -n payments

# 3. Verify previous pod health status
kubectl rollout status deployment/payment-gateway-service -n payments --timeout=120s

# 4. Confirm database connections revert to baseline
sqlplus -s sys/oracle@//localhost:1521/XEPDB1 as sysdba << EOF
SELECT COUNT(*) FROM V\$SESSION WHERE USERNAME = 'PAYMENT_APP';
EXIT;
EOF
```

---

## 6. Change Advisory Board (CAB) Approval (FR-14)

Formal approval granted at the Emergency/Normal CAB Review session:

- **CAB Meeting Date:** 10 Nov 2026, 16:00:00 UTC
- **CAB Chair:** Elena Rostova (Lead Oracle DBA) &bull; **Decision: APPROVED**
- **Service Delivery Lead:** Mahi Zaman &bull; **Decision: APPROVED**
- **Cyber & InfoSec Approver:** Sarah Jenkins &bull; **Decision: APPROVED**
- **Infrastructure Lead:** Marcus Vance &bull; **Decision: APPROVED**
- **Approval Comments:** *"Comprehensive test evidence provided. Low-risk zero-downtime deployment with verified 4-minute rollback plan. Authorized for release during Wednesday morning low-traffic maintenance window."*
