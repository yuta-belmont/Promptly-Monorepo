-- Create the enum type
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'plantype') THEN
        CREATE TYPE plantype AS ENUM ('free', 'plus', 'pro', 'credit');
    END IF;
END
$$;

-- Drop the default constraint
ALTER TABLE users ALTER COLUMN plan DROP DEFAULT;

-- Convert the column to use the enum
ALTER TABLE users 
  ALTER COLUMN plan TYPE plantype USING 'free'::plantype;
  
-- Set the default back
ALTER TABLE users 
  ALTER COLUMN plan SET DEFAULT 'free'::plantype; 