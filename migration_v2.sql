-- PulsePoll Database Migration v2
-- Non-destructive update for Custom Thank You messages and Required Question Toggles

-- 1. Add thank_you_message column to polls table
ALTER TABLE public.polls 
ADD COLUMN IF NOT EXISTS thank_you_message TEXT;

-- 2. Ensure is_required column exists on questions table with default true
ALTER TABLE public.questions 
ADD COLUMN IF NOT EXISTS is_required BOOLEAN DEFAULT true;
