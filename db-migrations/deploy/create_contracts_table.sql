-- Deploy insurance_db:create_contracts_table to pg

BEGIN;

CREATE TABLE contracts (
    id SERIAL PRIMARY KEY,
    contract_no TEXT UNIQUE NOT NULL,
    customer_name TEXT NOT NULL,
    policy_type TEXT NOT NULL,
    premium NUMERIC NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMIT;
