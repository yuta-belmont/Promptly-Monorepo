-- Add the new columns to the users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan VARCHAR(255) DEFAULT 'free' NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_expiry TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Create a type if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'plantype') THEN
        CREATE TYPE plantype AS ENUM ('free', 'plus', 'pro', 'credit');
    END IF;
END
$$;

-- Try to convert the column type (might fail if values are incompatible)
ALTER TABLE users 
  ALTER COLUMN plan TYPE plantype USING plan::plantype; 