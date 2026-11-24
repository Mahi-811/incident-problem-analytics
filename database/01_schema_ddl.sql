-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/01_schema_ddl.sql
-- Description: Oracle Database XE 21c DDL Schema definition
-- Author: Mahi Zaman
-- ============================================================================

-- Clean up existing tables safely if they exist
BEGIN
    FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN 
              ('CHANGES', 'INCIDENT_PROBLEM_LINK', 'PROBLEMS', 'INCIDENTS', 
               'SLA_MATRIX', 'REF_CATEGORIES', 'REF_SERVICES', 'REF_ASSIGNMENT_GROUPS')) 
    LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- ----------------------------------------------------------------------------
-- 1. Reference Table: SLA Matrix (FR-03, Section 5)
-- ----------------------------------------------------------------------------
CREATE TABLE SLA_MATRIX (
    PRIORITY                VARCHAR2(10)    NOT NULL,
    PRIORITY_NAME           VARCHAR2(50)    NOT NULL,
    RESPONSE_TARGET_HOURS   NUMBER(5,2)     NOT NULL,
    RESOLUTION_TARGET_HOURS NUMBER(5,2)     NOT NULL,
    DESCRIPTION             VARCHAR2(255),
    CREATED_AT              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT PK_SLA_MATRIX PRIMARY KEY (PRIORITY)
);

-- ----------------------------------------------------------------------------
-- 2. Reference Table: Categories (FR-03)
-- ----------------------------------------------------------------------------
CREATE TABLE REF_CATEGORIES (
    CATEGORY_CODE           VARCHAR2(30)    NOT NULL,
    CATEGORY_NAME           VARCHAR2(100)   NOT NULL,
    DESCRIPTION             VARCHAR2(255),
    CONSTRAINT PK_REF_CATEGORIES PRIMARY KEY (CATEGORY_CODE)
);

-- ----------------------------------------------------------------------------
-- 3. Reference Table: Services (FR-03)
-- ----------------------------------------------------------------------------
CREATE TABLE REF_SERVICES (
    SERVICE_CODE            VARCHAR2(50)    NOT NULL,
    SERVICE_NAME            VARCHAR2(100)   NOT NULL,
    CRITICAL_TIER           VARCHAR2(10)    DEFAULT 'Tier-2' NOT NULL,
    DESCRIPTION             VARCHAR2(255),
    CONSTRAINT PK_REF_SERVICES PRIMARY KEY (SERVICE_CODE)
);

-- ----------------------------------------------------------------------------
-- 4. Reference Table: Assignment Groups (FR-03)
-- ----------------------------------------------------------------------------
CREATE TABLE REF_ASSIGNMENT_GROUPS (
    GROUP_CODE              VARCHAR2(30)    NOT NULL,
    GROUP_NAME              VARCHAR2(100)   NOT NULL,
    LEAD_NAME               VARCHAR2(100),
    ESCALATION_EMAIL        VARCHAR2(100),
    CONSTRAINT PK_REF_ASSIGNMENT_GROUPS PRIMARY KEY (GROUP_CODE)
);

-- ----------------------------------------------------------------------------
-- 5. Primary Table: INCIDENTS (FR-01, FR-02, FR-05, Section 5)
-- ----------------------------------------------------------------------------
CREATE TABLE INCIDENTS (
    TICKET_ID               VARCHAR2(30)    NOT NULL,
    PRIORITY                VARCHAR2(10)    NOT NULL,
    CATEGORY                VARCHAR2(30)    NOT NULL,
    SERVICE                 VARCHAR2(50)    NOT NULL,
    ASSIGNMENT_GROUP        VARCHAR2(30)    NOT NULL,
    ROOT_CAUSE              VARCHAR2(200)   NOT NULL,
    STATUS                  VARCHAR2(20)    DEFAULT 'RESOLVED' NOT NULL,
    CREATED_TIME            TIMESTAMP       NOT NULL,
    RESOLVED_TIME           TIMESTAMP       NOT NULL,
    SLA_DUE_TIME            TIMESTAMP       NOT NULL,
    RESOLUTION_HOURS        NUMBER(8,2)     NOT NULL,
    IS_SLA_BREACH           NUMBER(1)       DEFAULT 0 NOT NULL,
    INGESTED_AT             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT PK_INCIDENTS PRIMARY KEY (TICKET_ID),
    CONSTRAINT FK_INC_PRIORITY FOREIGN KEY (PRIORITY) REFERENCES SLA_MATRIX(PRIORITY),
    CONSTRAINT FK_INC_CATEGORY FOREIGN KEY (CATEGORY) REFERENCES REF_CATEGORIES(CATEGORY_CODE),
    CONSTRAINT FK_INC_SERVICE FOREIGN KEY (SERVICE) REFERENCES REF_SERVICES(SERVICE_CODE),
    CONSTRAINT FK_INC_GROUP FOREIGN KEY (ASSIGNMENT_GROUP) REFERENCES REF_ASSIGNMENT_GROUPS(GROUP_CODE),
    CONSTRAINT CHK_INC_BREACH CHECK (IS_SLA_BREACH IN (0, 1)),
    CONSTRAINT CHK_INC_STATUS CHECK (STATUS IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'))
);

-- Optimized Performance Indexes (NFR-01)
CREATE INDEX IDX_INC_CREATED ON INCIDENTS(CREATED_TIME);
CREATE INDEX IDX_INC_RESOLVED ON INCIDENTS(RESOLVED_TIME);
CREATE INDEX IDX_INC_CAT_SVC_CAUSE ON INCIDENTS(CATEGORY, SERVICE, ROOT_CAUSE);
CREATE INDEX IDX_INC_PRIORITY ON INCIDENTS(PRIORITY);
CREATE INDEX IDX_INC_BREACH ON INCIDENTS(IS_SLA_BREACH);
CREATE INDEX IDX_INC_GROUP ON INCIDENTS(ASSIGNMENT_GROUP);

-- ----------------------------------------------------------------------------
-- 6. Table: PROBLEMS (FR-12, FR-13, Section 5)
-- ----------------------------------------------------------------------------
CREATE TABLE PROBLEMS (
    PROBLEM_ID              VARCHAR2(30)    NOT NULL,
    TITLE                   VARCHAR2(255)   NOT NULL,
    CATEGORY                VARCHAR2(30)    NOT NULL,
    SERVICE                 VARCHAR2(50)    NOT NULL,
    ROOT_CAUSE              VARCHAR2(200)   NOT NULL,
    RCA_5_WHYS              CLOB,
    KNOWN_ERROR_FLAG        NUMBER(1)       DEFAULT 0 NOT NULL,
    WORKAROUND              CLOB,
    STATUS                  VARCHAR2(30)    DEFAULT 'LOGGED' NOT NULL,
    CREATED_DATE            TIMESTAMP       DEFAULT CURRENT_TIMESTAMP NOT NULL,
    RESOLVED_DATE           TIMESTAMP,
    CONSTRAINT PK_PROBLEMS PRIMARY KEY (PROBLEM_ID),
    CONSTRAINT FK_PRB_CATEGORY FOREIGN KEY (CATEGORY) REFERENCES REF_CATEGORIES(CATEGORY_CODE),
    CONSTRAINT FK_PRB_SERVICE FOREIGN KEY (SERVICE) REFERENCES REF_SERVICES(SERVICE_CODE),
    CONSTRAINT CHK_PRB_KNOWN_ERR CHECK (KNOWN_ERROR_FLAG IN (0, 1)),
    CONSTRAINT CHK_PRB_STATUS CHECK (STATUS IN ('LOGGED', 'UNDER_INVESTIGATION', 'KNOWN_ERROR', 'CHANGE_PENDING', 'RESOLVED', 'CLOSED'))
);

-- ----------------------------------------------------------------------------
-- 7. Table: INCIDENT_PROBLEM_LINK (FR-12, Section 5)
-- ----------------------------------------------------------------------------
CREATE TABLE INCIDENT_PROBLEM_LINK (
    LINK_ID                 NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    TICKET_ID               VARCHAR2(30)    NOT NULL,
    PROBLEM_ID              VARCHAR2(30)    NOT NULL,
    LINKED_DATE             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT UQ_INCIDENT_PROBLEM UNIQUE (TICKET_ID, PROBLEM_ID),
    CONSTRAINT FK_LINK_INCIDENT FOREIGN KEY (TICKET_ID) REFERENCES INCIDENTS(TICKET_ID) ON DELETE CASCADE,
    CONSTRAINT FK_LINK_PROBLEM FOREIGN KEY (PROBLEM_ID) REFERENCES PROBLEMS(PROBLEM_ID) ON DELETE CASCADE
);

CREATE INDEX IDX_LINK_PRB ON INCIDENT_PROBLEM_LINK(PROBLEM_ID);
CREATE INDEX IDX_LINK_INC ON INCIDENT_PROBLEM_LINK(TICKET_ID);

-- ----------------------------------------------------------------------------
-- 8. Table: CHANGES (FR-14, Section 5)
-- ----------------------------------------------------------------------------
CREATE TABLE CHANGES (
    CHANGE_ID               VARCHAR2(30)    NOT NULL,
    PROBLEM_ID              VARCHAR2(30)    NOT NULL,
    CHANGE_TYPE             VARCHAR2(30)    DEFAULT 'NORMAL' NOT NULL,
    TITLE                   VARCHAR2(255)   NOT NULL,
    DESCRIPTION             CLOB            NOT NULL,
    RISK_LEVEL              VARCHAR2(20)    DEFAULT 'MEDIUM' NOT NULL,
    IMPACT_LEVEL            VARCHAR2(20)    DEFAULT 'MEDIUM' NOT NULL,
    TEST_PLAN               CLOB            NOT NULL,
    BACKOUT_PLAN            CLOB            NOT NULL,
    APPROVAL_STATUS         VARCHAR2(30)    DEFAULT 'SUBMITTED' NOT NULL,
    APPROVED_BY             VARCHAR2(100),
    APPROVAL_DATE           TIMESTAMP,
    SCHEDULED_START         TIMESTAMP,
    SCHEDULED_END           TIMESTAMP,
    IMPLEMENTATION_STATUS   VARCHAR2(30)    DEFAULT 'PLANNED' NOT NULL,
    CONSTRAINT PK_CHANGES PRIMARY KEY (CHANGE_ID),
    CONSTRAINT FK_CHG_PROBLEM FOREIGN KEY (PROBLEM_ID) REFERENCES PROBLEMS(PROBLEM_ID),
    CONSTRAINT CHK_CHG_TYPE CHECK (CHANGE_TYPE IN ('STANDARD', 'NORMAL', 'EMERGENCY')),
    CONSTRAINT CHK_CHG_RISK CHECK (RISK_LEVEL IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT CHK_CHG_IMPACT CHECK (IMPACT_LEVEL IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT CHK_CHG_APPROVAL CHECK (APPROVAL_STATUS IN ('SUBMITTED', 'PENDING_CAB', 'APPROVED', 'REJECTED')),
    CONSTRAINT CHK_CHG_STATUS CHECK (IMPLEMENTATION_STATUS IN ('PLANNED', 'IN_PROGRESS', 'SUCCESSFUL', 'BACKED_OUT', 'CANCELLED'))
);

CREATE INDEX IDX_CHG_PRB ON CHANGES(PROBLEM_ID);

COMMENT ON TABLE INCIDENTS IS 'ITIL Incident Records containing operational tickets over simulated 6 months';
COMMENT ON TABLE PROBLEMS IS 'ITIL Problem Records for root causes identified from recurring incidents';
COMMENT ON TABLE CHANGES IS 'ITIL Change Request records for documented fixes and risk assessments';
COMMENT ON TABLE SLA_MATRIX IS 'SLA Response and Resolution targets configured by ticket priority';
