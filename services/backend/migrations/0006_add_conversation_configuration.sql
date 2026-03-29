ALTER TABLE conversations ADD COLUMN model TEXT;
ALTER TABLE conversations ADD COLUMN reasoning_effort TEXT;
ALTER TABLE conversations ADD COLUMN agent_worker_reasoning_effort TEXT;
ALTER TABLE conversations ADD COLUMN service_tier TEXT;

UPDATE conversations
   SET reasoning_effort = COALESCE(reasoning_effort, 'high'),
       service_tier = COALESCE(service_tier, 'default')
 WHERE reasoning_effort IS NULL
    OR service_tier IS NULL;
