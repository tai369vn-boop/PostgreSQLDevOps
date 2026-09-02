-- Verify insurance_db:add_notes_column on pg
BEGIN;
SELECT notes FROM contracts WHERE false;
COMMIT;