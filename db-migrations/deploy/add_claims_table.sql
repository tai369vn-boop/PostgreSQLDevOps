-- Deploy insurance_db:add_claims_table to pg
-- requires: create_contracts_table

BEGIN;

CREATE TABLE claims (
    id SERIAL PRIMARY KEY,
    contract_id INT NOT NULL REFERENCES contracts(id),
    claim_no TEXT UNIQUE NOT NULL,
    amount_claimed NUMERIC NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMIT;
