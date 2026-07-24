BEGIN;

-- Create isolated schemas for separate tenants
CREATE SCHEMA IF NOT EXISTS tenant_alpha;
CREATE SCHEMA IF NOT EXISTS tenant_beta;

-- Tenant Alpha Orders Table
CREATE TABLE IF NOT EXISTS tenant_alpha.orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_name VARCHAR(100) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tenant Beta Orders Table
CREATE TABLE IF NOT EXISTS tenant_beta.orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_name VARCHAR(100) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMIT;