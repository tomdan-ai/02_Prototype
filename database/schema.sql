-- SwiftDrop Logistics: schema
-- Runs automatically on first Postgres start (mounted to /docker-entrypoint-initdb.d).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Customers: one row per WhatsApp phone number (normalized to +234...)
CREATE TABLE customers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(20) NOT NULL UNIQUE,
    name        VARCHAR(120),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Conversations: temporary state for multi-message flows
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    current_intent  VARCHAR(40),
    current_state   VARCHAR(40) NOT NULL DEFAULT 'IDLE',
    context         JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_conversations_active ON conversations (customer_id) WHERE is_active;

-- Deliveries: created by the delivery-request flow or seeded for tracking demos
CREATE TABLE deliveries (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_number      VARCHAR(20) NOT NULL UNIQUE
                         CHECK (tracking_number ~ '^SD-[0-9]{4,}$'),
    customer_id          UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    pickup_location      VARCHAR(120) NOT NULL,
    delivery_location    VARCHAR(120) NOT NULL,
    package_description  VARCHAR(200),
    package_size         VARCHAR(10) NOT NULL CHECK (package_size IN ('SMALL','MEDIUM','LARGE')),
    recipient_name       VARCHAR(120) NOT NULL,
    recipient_phone      VARCHAR(20) NOT NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                         CHECK (status IN ('PENDING','CONFIRMED','PICKED_UP','IN_TRANSIT',
                                           'OUT_FOR_DELIVERY','DELIVERED','CANCELLED','FAILED')),
    delivery_fee         INTEGER NOT NULL CHECK (delivery_fee >= 0),   -- NGN, whole naira
    scheduled_date       DATE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_deliveries_customer ON deliveries (customer_id);

-- Generates tracking numbers as SD-1100, SD-1101, ... (seed data already uses SD-1001/1002/1042)
CREATE SEQUENCE IF NOT EXISTS tracking_number_seq START WITH 1100;

-- Messages: inbound and outbound. external_id is UNIQUE for idempotency.
CREATE TABLE messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id      VARCHAR(100) UNIQUE,              -- provider message_id (dedupe key)
    customer_id      UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    conversation_id  UUID REFERENCES conversations(id) ON DELETE SET NULL,
    direction        VARCHAR(10) NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND')),
    body             TEXT NOT NULL,
    intent           VARCHAR(40),
    status           VARCHAR(20) NOT NULL DEFAULT 'RECEIVED'
                     CHECK (status IN ('RECEIVED','PROCESSED','FAILED')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_customer ON messages (customer_id, created_at);

-- Escalations: human hand-off queue
CREATE TABLE escalations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    delivery_id   UUID REFERENCES deliveries(id) ON DELETE SET NULL,
    reason        TEXT NOT NULL,
    priority      VARCHAR(10) NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('LOW','MEDIUM','HIGH')),
    status        VARCHAR(15) NOT NULL DEFAULT 'OPEN'
                  CHECK (status IN ('OPEN','IN_PROGRESS','RESOLVED')),
    assigned_to   VARCHAR(100),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at   TIMESTAMPTZ
);
CREATE INDEX idx_escalations_open ON escalations (status) WHERE status <> 'RESOLVED';

-- Audit log: append-only record of what happened and why
CREATE TABLE audit_logs (
    id           BIGSERIAL PRIMARY KEY,
    event_type   VARCHAR(50) NOT NULL,
    entity_type  VARCHAR(30),
    entity_id    VARCHAR(64),
    details      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs (entity_type, entity_id);
CREATE INDEX idx_audit_event_time ON audit_logs (event_type, created_at);

-- Keep updated_at honest
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customers_updated     BEFORE UPDATE ON customers     FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_conversations_updated BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_deliveries_updated    BEFORE UPDATE ON deliveries    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
