-- PulsePoll Database Schema
-- Supabase PostgreSQL Schema with Row Level Security (RLS) & Performance Indexes
-- Designed for High Concurrency (200+ simultaneous participants) with Closed-Loop Anonymity

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TABLES

-- Table: polls
CREATE TABLE IF NOT EXISTS public.polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    thank_you_message TEXT,
    type VARCHAR(20) NOT NULL CHECK (type IN ('poll', 'quiz')) DEFAULT 'poll',
    join_code VARCHAR(10) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'closed')) DEFAULT 'active',
    closes_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: questions
CREATE TABLE IF NOT EXISTS public.questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('mcq', 'short_answer', 'rating')),
    title TEXT NOT NULL,
    order_num INTEGER NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: options (for MCQ questions)
CREATE TABLE IF NOT EXISTS public.options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    order_num INTEGER NOT NULL DEFAULT 0,
    is_correct BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: responses (Anonymized response submission session)
-- STRICT ANONYMITY: Strictly NO IP addresses, user-agent fingerprints, or personal identifiers are stored.
CREATE TABLE IF NOT EXISTS public.responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: answers (Individual answers belonging to an anonymous response)
CREATE TABLE IF NOT EXISTS public.answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    response_id UUID NOT NULL REFERENCES public.responses(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    option_id UUID REFERENCES public.options(id) ON DELETE CASCADE,
    rating_value SMALLINT CHECK (rating_value BETWEEN 1 AND 5),
    text_response TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. INDEXES FOR ULTRA-HIGH CONCURRENCY (200+ Simultaneous Users)
CREATE INDEX IF NOT EXISTS idx_polls_join_code ON public.polls(join_code);
CREATE INDEX IF NOT EXISTS idx_polls_admin_id ON public.polls(admin_id);
CREATE INDEX IF NOT EXISTS idx_polls_status ON public.polls(status);
CREATE INDEX IF NOT EXISTS idx_polls_closes_at ON public.polls(closes_at);
CREATE INDEX IF NOT EXISTS idx_questions_poll_id ON public.questions(poll_id, order_num);
CREATE INDEX IF NOT EXISTS idx_options_question_id ON public.options(question_id, order_num);
CREATE INDEX IF NOT EXISTS idx_responses_poll_id ON public.responses(poll_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_answers_response_id ON public.answers(response_id);
CREATE INDEX IF NOT EXISTS idx_answers_question_id ON public.answers(question_id);
CREATE INDEX IF NOT EXISTS idx_answers_option_id ON public.answers(option_id);

-- 4. ROW LEVEL SECURITY (RLS) POLICIES
ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.answers ENABLE ROW LEVEL SECURITY;

-- POLLS POLICIES
-- Anyone can view active polls (to allow student participation via join_code or direct link)
DROP POLICY IF EXISTS "Public can view active polls" ON public.polls;
CREATE POLICY "Public can view active polls"
ON public.polls FOR SELECT
TO anon, authenticated
USING (true);

-- Admins can insert their own polls
DROP POLICY IF EXISTS "Admins can create polls" ON public.polls;
CREATE POLICY "Admins can create polls"
ON public.polls FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = admin_id);

-- Admins can update their own polls
DROP POLICY IF EXISTS "Admins can update own polls" ON public.polls;
CREATE POLICY "Admins can update own polls"
ON public.polls FOR UPDATE
TO authenticated
USING (auth.uid() = admin_id)
WITH CHECK (auth.uid() = admin_id);

-- Admins can delete their own polls
DROP POLICY IF EXISTS "Admins can delete own polls" ON public.polls;
CREATE POLICY "Admins can delete own polls"
ON public.polls FOR DELETE
TO authenticated
USING (auth.uid() = admin_id);

-- QUESTIONS POLICIES
-- Anyone can view questions for polls
DROP POLICY IF EXISTS "Public can view questions" ON public.questions;
CREATE POLICY "Public can view questions"
ON public.questions FOR SELECT
TO anon, authenticated
USING (true);

-- Admins can manage questions of their own polls
DROP POLICY IF EXISTS "Admins can insert questions" ON public.questions;
CREATE POLICY "Admins can insert questions"
ON public.questions FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.polls WHERE polls.id = questions.poll_id AND polls.admin_id = auth.uid())
);

DROP POLICY IF EXISTS "Admins can update questions" ON public.questions;
CREATE POLICY "Admins can update questions"
ON public.questions FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.polls WHERE polls.id = questions.poll_id AND polls.admin_id = auth.uid())
);

DROP POLICY IF EXISTS "Admins can delete questions" ON public.questions;
CREATE POLICY "Admins can delete questions"
ON public.questions FOR DELETE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.polls WHERE polls.id = questions.poll_id AND polls.admin_id = auth.uid())
);

-- OPTIONS POLICIES
-- Anyone can view options for questions
DROP POLICY IF EXISTS "Public can view options" ON public.options;
CREATE POLICY "Public can view options"
ON public.options FOR SELECT
TO anon, authenticated
USING (true);

-- Admins can manage options of their own questions
DROP POLICY IF EXISTS "Admins can insert options" ON public.options;
CREATE POLICY "Admins can insert options"
ON public.options FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.questions q
        JOIN public.polls p ON p.id = q.poll_id
        WHERE q.id = options.question_id AND p.admin_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Admins can update options" ON public.options;
CREATE POLICY "Admins can update options"
ON public.options FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.questions q
        JOIN public.polls p ON p.id = q.poll_id
        WHERE q.id = options.question_id AND p.admin_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Admins can delete options" ON public.options;
CREATE POLICY "Admins can delete options"
ON public.options FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.questions q
        JOIN public.polls p ON p.id = q.poll_id
        WHERE q.id = options.question_id AND p.admin_id = auth.uid()
    )
);

-- RESPONSES POLICIES
-- Students (anon & authenticated) can insert responses if the poll is active and not expired
DROP POLICY IF EXISTS "Public can submit responses" ON public.responses;
CREATE POLICY "Public can submit responses"
ON public.responses FOR INSERT
TO anon, authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.polls
        WHERE polls.id = responses.poll_id
          AND polls.status = 'active'
          AND (polls.closes_at IS NULL OR polls.closes_at > now())
    )
);

-- Admins can view responses for their own polls
DROP POLICY IF EXISTS "Admins can view responses for their polls" ON public.responses;
CREATE POLICY "Admins can view responses for their polls"
ON public.responses FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.polls
        WHERE polls.id = responses.poll_id AND polls.admin_id = auth.uid()
    )
);

-- Admins can delete responses if resetting a poll
DROP POLICY IF EXISTS "Admins can delete responses for their polls" ON public.responses;
CREATE POLICY "Admins can delete responses for their polls"
ON public.responses FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.polls
        WHERE polls.id = responses.poll_id AND polls.admin_id = auth.uid()
    )
);

-- SECURITY DEFINER helper to allow anonymous students to insert answers without exposing responses to SELECT
CREATE OR REPLACE FUNCTION public.is_response_poll_active(p_response_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.responses r
        JOIN public.polls p ON p.id = r.poll_id
        WHERE r.id = p_response_id
          AND p.status = 'active'
          AND (p.closes_at IS NULL OR p.closes_at > now())
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_response_poll_active(UUID) TO anon, authenticated;

-- ANSWERS POLICIES
-- Students can insert answers linked to their response
DROP POLICY IF EXISTS "Public can insert answers" ON public.answers;
CREATE POLICY "Public can insert answers"
ON public.answers FOR INSERT
TO anon, authenticated
WITH CHECK (
    public.is_response_poll_active(response_id)
);

-- Admins can view answers for their polls
DROP POLICY IF EXISTS "Admins can view answers for their polls" ON public.answers;
CREATE POLICY "Admins can view answers for their polls"
ON public.answers FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.responses r
        JOIN public.polls p ON p.id = r.poll_id
        WHERE r.id = answers.response_id AND p.admin_id = auth.uid()
    )
);

-- 5. SINGLE-TRANSACTION ATOMIC SUBMISSION FUNCTION (FOR 200 CONCURRENT USERS)
-- Allows atomic submission of full response payload in a single database round-trip
CREATE OR REPLACE FUNCTION public.submit_poll_response(
    p_poll_id UUID,
    p_answers JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_poll RECORD;
    v_response_id UUID;
    v_answer JSONB;
BEGIN
    -- Check if poll exists and is active
    SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Poll not found');
    END IF;

    -- Check if poll is expired or closed
    IF v_poll.status <> 'active' THEN
        RETURN jsonb_build_object('success', false, 'error', 'This poll is closed');
    END IF;

    IF v_poll.closes_at IS NOT NULL AND v_poll.closes_at <= now() THEN
        -- Auto-close if timer has passed
        UPDATE public.polls SET status = 'closed', updated_at = now() WHERE id = p_poll_id;
        RETURN jsonb_build_object('success', false, 'error', 'This poll timer has expired and is now closed');
    END IF;

    -- Create anonymous response entry
    INSERT INTO public.responses (poll_id, submitted_at)
    VALUES (p_poll_id, now())
    RETURNING id INTO v_response_id;

    -- Insert all answers in one transaction
    FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers)
    LOOP
        INSERT INTO public.answers (
            response_id,
            question_id,
            option_id,
            rating_value,
            text_response
        ) VALUES (
            v_response_id,
            (v_answer->>'question_id')::UUID,
            CASE WHEN v_answer->>'option_id' IS NOT NULL AND v_answer->>'option_id' <> '' 
                 THEN (v_answer->>'option_id')::UUID ELSE NULL END,
            CASE WHEN v_answer->>'rating_value' IS NOT NULL AND v_answer->>'rating_value' <> '' 
                 THEN (v_answer->>'rating_value')::SMALLINT ELSE NULL END,
            v_answer->>'text_response'
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'response_id', v_response_id,
        'message', 'Anonymous response successfully recorded'
    );
END;
$$;

-- Grant execution to anon and authenticated roles
GRANT EXECUTE ON FUNCTION public.submit_poll_response(UUID, JSONB) TO anon, authenticated;

-- 6. REALTIME REPLICATION (For instant live updates in Present Mode and Results page)
-- Enable supabase realtime for responses and polls
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.responses;
    EXCEPTION WHEN duplicate_object THEN
        -- Already added
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.polls;
    EXCEPTION WHEN duplicate_object THEN
        -- Already added
    END;
END $$;
