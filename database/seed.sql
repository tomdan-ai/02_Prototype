-- SwiftDrop Logistics: SYNTHETIC seed data only. No real customer information.

INSERT INTO customers (id, phone, name) VALUES
  ('00000000-0000-0000-0000-000000000001', '+2348000000001', 'Test Customer One'),
  ('00000000-0000-0000-0000-000000000002', '+2348000000002', 'Test Customer Two');

-- Pre-existing deliveries for tracking and rescheduling demos
INSERT INTO deliveries
  (tracking_number, customer_id, pickup_location, delivery_location, package_description,
   package_size, recipient_name, recipient_phone, status, delivery_fee, scheduled_date)
VALUES
  ('SD-1001', '00000000-0000-0000-0000-000000000001', 'Uyo', 'Aba', 'Electronics accessories',
   'SMALL', 'Test Recipient A', '+2348000000101', 'IN_TRANSIT', 3000, CURRENT_DATE),
  ('SD-1002', '00000000-0000-0000-0000-000000000001', 'Aba', 'Uyo', 'Documents',
   'SMALL', 'Test Recipient B', '+2348000000102', 'PENDING', 3000, CURRENT_DATE + 2),
  ('SD-1042', '00000000-0000-0000-0000-000000000002', 'Uyo', 'Port Harcourt', 'Clothing',
   'LARGE', 'Test Recipient C', '+2348000000103', 'DELIVERED', 6000, CURRENT_DATE - 1);

-- Starter audit entry so the audit view is never empty during the demo
INSERT INTO audit_logs (event_type, entity_type, entity_id, details)
VALUES ('SEED_LOADED', 'system', NULL, '{"note": "synthetic seed data"}');
