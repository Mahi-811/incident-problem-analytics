# ITIL Problem Record: PRB-2026-001

**System:** ITIL Problem & Incident Analytics  
**Document Ref:** PRB-2026-001  
**Author / Problem Coordinator:** Mahi Zaman (Service Delivery Lead)  
**Date Logged:** 01 Nov 2026 09:30:00 UTC  
**Target Service:** `PAYMENT_GATEWAY` (Payment Processing Gateway)  
**Category:** `SOFTWARE` (Software & Application Integrations)  
**Priority:** P1 – Critical / Revenue Blocker  
**Current Status:** Problem Solved & Verified (Post-Fix PIR Completed)

---

## 1. Problem Overview & Symptom Description

### 1.1 Problem Statement
During peak transaction hours (particularly month-end billing cycles and promotion windows), the `PAYMENT_GATEWAY` microservice experienced severe intermittent degradation. Client requests timed out with `HTTP 504 Gateway Timeout` and checkout API invocations failed, resulting in customer drop-offs and operational escalation to Tier-1 Service Desk.

### 1.2 Impact Assessment
- **Business Impact:** High. Estimated 4,200 payment transactions delayed or failed across 6 months.
- **Affected Services:** Payment Processing Gateway, Core Banking Settlement, Checkout API.
- **User Groups Affected:** Retail consumers, corporate merchants, automated subscription rebilling.

---

## 2. Linked Incidents (FR-12)

The analytics engine identified **38 recurring incident tickets** matching Category `SOFTWARE`, Service `PAYMENT_GATEWAY`, and Root Cause `Connection Pool Exhaustion under Peak Traffic` across the 6-month simulated operational period.

| Incident ID | Created Timestamp | Resolved Timestamp | Priority | Resolution (hrs) | SLA Status |
|:---|:---|:---|:---:|:---:|:---:|
| `INC-2026-0001` | 2026-06-03 14:22:10 | 2026-06-03 15:45:00 | P1 | 1.38 | Met |
| `INC-2026-0014` | 2026-06-18 10:15:42 | 2026-06-18 12:00:30 | P1 | 1.75 | Met |
| `INC-2026-0029` | 2026-06-29 18:30:15 | 2026-06-29 23:45:00 | P1 | 5.25 | **Breached** |
| `INC-2026-0045` | 2026-07-04 11:10:05 | 2026-07-04 12:50:00 | P2 | 1.67 | Met |
| `INC-2026-0062` | 2026-07-16 16:40:22 | 2026-07-16 18:15:00 | P1 | 1.58 | Met |
| `INC-2026-0079` | 2026-07-30 20:12:00 | 2026-07-31 02:30:00 | P1 | 6.30 | **Breached** |
| `INC-2026-0098` | 2026-08-08 09:25:10 | 2026-08-08 11:05:00 | P2 | 1.67 | Met |
| `INC-2026-0120` | 2026-08-28 17:50:30 | 2026-08-28 23:10:00 | P1 | 5.33 | **Breached** |
| `INC-2026-0145` | 2026-09-05 14:10:18 | 2026-09-05 16:00:00 | P1 | 1.83 | Met |
| `INC-2026-0172` | 2026-09-29 19:05:40 | 2026-09-30 01:15:00 | P1 | 6.16 | **Breached** |
| `INC-2026-0210` | 2026-10-12 11:30:00 | 2026-10-12 13:10:00 | P2 | 1.67 | Met |
| `INC-2026-0248` | 2026-10-30 21:00:00 | 2026-10-31 03:00:00 | P1 | 6.00 | **Breached** |
| *(26 additional tickets linked in Oracle DB table `INCIDENT_PROBLEM_LINK`)* | ... | ... | ... | ... | ... |

**Repeat Pattern Summary:**
- Total Linked Tickets: **38**
- SLA Breaches: **7 (18.4%)**
- Average MTTR: **3.42 hours**
- Max 30-Day Cluster Burst: **9 tickets**

---

## 3. Root Cause Analysis (5 Whys Methodology) (FR-13)

The cross-functional Problem Investigation Team (App Dev, DBA, and SRE) conducted a structured 5 Whys RCA:

```
[Problem: Payment processing transactions timed out with HTTP 504 during peak volume]
                                │
                          Why 1? ▼
[Payment Gateway worker threads stalled waiting for JDBC database connections]
                                │
                          Why 2? ▼
[HikariCP datasource pool was completely saturated (20/20 active connections)]
                                │
                          Why 3? ▼
[Outbound merchant webhook calls were executed synchronously within active database transactions]
                                │
                          Why 4? ▼
[Slow merchant endpoints held database connections open for up to 30 seconds each]
                                │
                          Why 5? ▼ (Root Cause)
[Architectural defect: Lack of asynchronous event decoupling for external I/O & missing connection pool exhaustion alerts]
```

1. **Why 1:** *Why did payment API requests time out?*  
   Worker threads in the Spring Boot payment service blocked indefinitely while waiting to acquire a connection from the `HikariCP` pool (`ConnectionTimeoutException: Connection is not available, request timed out after 30000ms`).
2. **Why 2:** *Why were no database connections available?*  
   The connection pool was pinned at maximum capacity (20 active connections) for prolonged intervals.
3. **Why 3:** *Why did connections remain occupied for so long?*  
   The legacy `MerchantNotificationService` executed synchronous HTTP POST callbacks to third-party merchant URLs **inside** the transactional boundary (`@Transactional`).
4. **Why 4:** *Why did callbacks take excessive time?*  
   Slow or unresponsive merchant endpoints introduced 15–30 second latencies, during which the underlying relational database connection was idle but locked to that thread.
5. **Why 5 (Root Cause):** *Why was this design allowed in production?*  
   The application lacked architectural decoupling between transactional persistence and external I/O notifications, and there were no Prometheus telemetry monitors on pool saturation.

---

## 4. Known Error Record (KER) (FR-13)

- **Known Error ID:** `KER-2026-018`
- **Component:** `payment-gateway-service / HikariCP Pool`
- **Error Condition:** Peak concurrency exceeding 100 TPS combined with external webhook latency > 2s triggers complete thread pool and connection starvation.
- **Permanent Fix Target:** Change Request `CHG-2026-042`.

---

## 5. Interim Workaround Procedures (FR-13)

Pending permanent code refactoring, Tier-1 and Tier-2 support teams were instructed to execute the following standard operating procedure upon detection of connection pool saturation:

1. **Immediate Service Pod Rolling Restart:**
   ```powershell
   # Recycle payment pods with zero downtime
   kubectl rollout restart deployment/payment-gateway-service -n payments
   ```
2. **Dynamic Connection Pool Expansion:**
   ```bash
   # Issue dynamic Spring Cloud Config refresh to increase max pool size
   curl -X POST "http://config-server.internal:8888/actuator/bus-refresh" \
     -H "Content-Type: application/json" \
     -d '{"spring.datasource.hikari.maximum-pool-size": 60}'
   ```
3. **Emergency Circuit Breaker Activation:**
   ```bash
   # Route merchant notifications to emergency disk buffer
   curl -X POST "http://payment-gateway.internal/admin/circuit-breaker/merchant-callbacks/open"
   ```

---

## 6. Permanent Resolution & Change Handover

- **Remediation Plan:** Refactor merchant callback mechanism to publish events asynchronously onto an Apache Kafka queue (`merchant.notifications.v1`), decouple database transactions, and expand connection pool parameters.
- **Handover to Change Management:** Logged as **Normal Change Request CHG-2026-042**.
