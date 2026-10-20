-- Quiz Desk on Supabase
-- Faculty sign in with Supabase Auth (email + password) and work through row-level security.
-- Students never touch tables: they sign in with roll number + PIN through SECURITY DEFINER
-- functions that hand back a short-lived session token, so answer keys and other students'
-- data are never readable from the browser, and the timer is enforced here, not in the page.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tables
create table public.groups (
  id            text primary key check (id ~ '^[A-Za-z0-9]{1,12}$'),
  name          text not null,
  student_limit int  not null default 30 check (student_limit between 1 and 500),
  created_at    timestamptz not null default now()
);

create table public.faculty (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 120),
  email       text not null,
  role        text not null default 'faculty' check (role in ('admin', 'faculty')),
  status      text not null default 'pending' check (status in ('pending', 'active', 'disabled')),
  approved_by uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

create table public.students (
  id            uuid primary key default gen_random_uuid(),
  group_id      text not null references public.groups(id) on delete cascade,
  roll          text not null check (length(roll) between 1 and 40),
  name          text not null default '',
  email         text not null default '',
  division      text not null default '',
  pin_hash      text,
  pin_set       boolean not null default false,
  failed_logins int  not null default 0,
  locked_until  timestamptz,
  created_at    timestamptz not null default now(),
  unique (group_id, roll)
);

-- One shared bank for every group.
create table public.questions (
  id         uuid primary key default gen_random_uuid(),
  text       text not null check (length(text) between 1 and 8000),
  options    jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 6),
  answer     int  not null check (answer >= 0),
  topic      text not null default 'General',
  difficulty text not null default 'medium' check (difficulty in ('easy', 'medium', 'hard')),
  marks      numeric not null default 1 check (marks > 0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create unique index questions_text_unique on public.questions (md5(lower(text)));

-- A quiz keeps a snapshot of its questions (with answers) so later bank edits never change it.
create table public.quizzes (
  id             uuid primary key default gen_random_uuid(),
  group_id       text not null references public.groups(id) on delete cascade,
  title          text not null check (length(trim(title)) between 1 and 200),
  duration_min   int  not null check (duration_min between 1 and 600),
  status         text not null default 'draft' check (status in ('draft', 'live', 'closed')),
  released       boolean not null default false,
  shuffle        boolean not null default true,
  proctor        jsonb not null default '{"penalty":1,"free":1,"maxV":5}',
  questions      jsonb not null,          -- [{id,text,options,answer,marks,topic}]
  total_marks    numeric not null,
  assigned_rolls text[] not null,
  divisions      text[] not null default '{}',
  created_by     uuid references auth.users(id),
  created_by_name text not null default '',
  started_by_name text not null default '',
  started_at     timestamptz,
  closed_by_name text not null default '',
  closed_at      timestamptz,
  created_at     timestamptz not null default now()
);
create index quizzes_group on public.quizzes (group_id);

create table public.attempts (
  id           uuid primary key default gen_random_uuid(),
  quiz_id      uuid not null references public.quizzes(id) on delete cascade,
  student_id   uuid not null references public.students(id) on delete cascade,
  started_at   timestamptz not null default now(),
  deadline     timestamptz not null,
  submitted_at timestamptz,
  auto         boolean not null default false,
  answers      jsonb not null default '{}',   -- {question_id: original option index}
  marked       jsonb not null default '{}',
  updated_at   timestamptz not null default now(),
  unique (quiz_id, student_id)
);
create index attempts_quiz on public.attempts (quiz_id);

create table public.violations (
  id         bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  type       text not null check (type in ('tab','copy','cut','paste','menu','drop','fullscreen','screenshot')),
  at         timestamptz not null default now(),
  secs       int
);
create index violations_attempt on public.violations (attempt_id);

create table public.student_sessions (
  token_hash text primary key,
  student_id uuid not null references public.students(id) on delete cascade,
  expires_at timestamptz not null
);
create index student_sessions_student on public.student_sessions (student_id);

create table public.activity (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  user_id  uuid references auth.users(id),
  name     text not null default '',
  group_id text,
  action   text not null,
  detail   text not null default ''
);
create index activity_at on public.activity (at desc);

-- ---------------------------------------------------------------- faculty access
create or replace function public.is_faculty() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from faculty where user_id = auth.uid() and status = 'active');
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from faculty where user_id = auth.uid() and status = 'active' and role = 'admin');
$$;

alter table public.groups           enable row level security;
alter table public.faculty          enable row level security;
alter table public.students         enable row level security;
alter table public.questions        enable row level security;
alter table public.quizzes          enable row level security;
alter table public.attempts         enable row level security;
alter table public.violations       enable row level security;
alter table public.student_sessions enable row level security;   -- no policies: functions only
alter table public.activity         enable row level security;

create policy groups_read   on public.groups for select to authenticated using (is_faculty());
create policy groups_admin  on public.groups for all    to authenticated using (is_admin()) with check (is_admin());

create policy faculty_read  on public.faculty for select to authenticated using (user_id = auth.uid() or is_faculty());
create policy faculty_admin on public.faculty for update to authenticated using (is_admin()) with check (is_admin());
create policy faculty_admin_delete on public.faculty for delete to authenticated using (is_admin() and user_id <> auth.uid());

create policy students_all   on public.students   for all to authenticated using (is_faculty()) with check (is_faculty());
create policy questions_all  on public.questions  for all to authenticated using (is_faculty()) with check (is_faculty());
create policy quizzes_all    on public.quizzes    for all to authenticated using (is_faculty()) with check (is_faculty());
create policy attempts_read  on public.attempts   for select to authenticated using (is_faculty());
create policy attempts_del   on public.attempts   for delete to authenticated using (is_faculty());
create policy violations_read on public.violations for select to authenticated using (is_faculty());
create policy activity_read  on public.activity   for select to authenticated using (is_faculty());
create policy activity_write on public.activity   for insert to authenticated with check (is_faculty() and user_id = auth.uid());

-- The PIN hash is never readable or writable from the browser, even by faculty: they get the
-- other columns only, and set PINs through set_student_pins().
revoke all on public.students from anon, authenticated;
grant select (id, group_id, roll, name, email, division, pin_set, failed_logins, locked_until, created_at) on public.students to authenticated;
grant insert (group_id, roll, name, email, division) on public.students to authenticated;
grant update (group_id, roll, name, email, division, failed_logins, locked_until) on public.students to authenticated;
grant delete on public.students to authenticated;
-- Sessions are for the student functions only.
revoke all on public.student_sessions from anon, authenticated;

-- A signed-in person asks to join as faculty; an admin approves. The very first person becomes admin.
create or replace function public.register_faculty(p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare v_email text; v_first boolean;
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'Enter your name.'; end if;
  select email into v_email from auth.users where id = auth.uid();
  perform pg_advisory_xact_lock(hashtext('quiz-desk-first-admin'));
  v_first := not exists (select 1 from faculty where role = 'admin' and status = 'active');
  insert into faculty (user_id, name, email, role, status)
  values (auth.uid(), trim(p_name), coalesce(v_email, ''), case when v_first then 'admin' else 'faculty' end,
          case when v_first then 'active' else 'pending' end)
  on conflict (user_id) do update set name = excluded.name;
  if v_first then
    insert into activity (user_id, name, action, detail) values (auth.uid(), trim(p_name), 'Became administrator', v_email);
  end if;
  return (select status from faculty where user_id = auth.uid());
end $$;

-- Faculty set student PINs; only the hash is stored.
create or replace function public.set_student_pins(p_pins jsonb) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0;
begin
  if not is_faculty() then raise exception 'Faculty only.'; end if;
  for r in select key::uuid as id, value #>> '{}' as pin from jsonb_each(p_pins) loop
    if r.pin !~ '^[0-9]{4,8}$' then raise exception 'PINs must be 4 to 8 digits.'; end if;
    update students set pin_hash = crypt(r.pin, gen_salt('bf', 8)), pin_set = true, failed_logins = 0, locked_until = null where id = r.id;
    delete from student_sessions where student_id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Faculty change a quiz's status; the database records who and when.
create or replace function public.set_quiz_status(p_quiz uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not is_faculty() then raise exception 'Faculty only.'; end if;
  select name into v_name from faculty where user_id = auth.uid();
  if p_status = 'live' then
    update quizzes set status = 'live', started_by_name = v_name, started_at = now() where id = p_quiz;
  elsif p_status = 'closed' then
    update quizzes set status = 'closed', closed_by_name = v_name, closed_at = now() where id = p_quiz;
    -- Everyone still answering is submitted now, with what they had saved.
    update attempts set submitted_at = least(now(), deadline), auto = true, updated_at = now()
     where quiz_id = p_quiz and submitted_at is null;
  else
    raise exception 'Unknown status %', p_status;
  end if;
end $$;

-- ---------------------------------------------------------------- student functions
create or replace function public._student_from_token(p_token text) returns public.students
language plpgsql stable security definer set search_path = public, extensions as $$
declare s students;
begin
  select st.* into s from student_sessions ss join students st on st.id = ss.student_id
   where ss.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and ss.expires_at > now();
  if s.id is null then raise exception 'SESSION_EXPIRED' using hint = 'Sign in again with your roll number and PIN.'; end if;
  return s;
end $$;

create or replace function public._public_quiz(q public.quizzes) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', q.id, 'title', q.title, 'duration_min', q.duration_min, 'status', q.status,
    'released', q.released, 'total_marks', q.total_marks, 'n', jsonb_array_length(q.questions), 'proctor', q.proctor);
$$;

-- Wrong PINs return an error object instead of raising, so the failed-attempt count is kept
-- (raising would roll it back). Five wrong PINs lock that roll number for 2 minutes.
create or replace function public.student_login(p_group text, p_roll text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s students; v_token text; v_fails int;
  v_wrong constant jsonb := jsonb_build_object('error', 'WRONG_LOGIN', 'hint', 'Check your roll number and PIN, and that this is your group''s link.');
begin
  select * into s from students where group_id = upper(trim(p_group)) and roll = upper(trim(p_roll));
  if s.id is null or s.pin_hash is null then perform pg_sleep(0.4); return v_wrong; end if;
  if s.locked_until is not null and s.locked_until > now() then
    return jsonb_build_object('error', 'LOCKED', 'hint', format('Too many wrong PINs. Try again in %s seconds, or ask your teacher.', ceil(extract(epoch from s.locked_until - now()))));
  end if;
  if crypt(coalesce(p_pin, ''), s.pin_hash) <> s.pin_hash then
    update students set failed_logins = failed_logins + 1,
      locked_until = case when failed_logins + 1 >= 5 then now() + interval '2 minutes' else null end
     where id = s.id returning failed_logins into v_fails;
    perform pg_sleep(0.4);
    if v_fails >= 5 then
      return jsonb_build_object('error', 'LOCKED', 'hint', 'Too many wrong PINs. Try again in 120 seconds, or ask your teacher.');
    end if;
    return v_wrong;
  end if;
  update students set failed_logins = 0, locked_until = null where id = s.id;
  delete from student_sessions where expires_at < now();
  v_token := encode(gen_random_bytes(24), 'hex');
  insert into student_sessions (token_hash, student_id, expires_at)
  values (encode(digest(v_token, 'sha256'), 'hex'), s.id, now() + interval '12 hours');
  return jsonb_build_object('token', v_token, 'roll', s.roll, 'name', s.name, 'group', s.group_id,
    'group_name', (select name from groups where id = s.group_id));
end $$;

create or replace function public.student_quizzes(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s students := _student_from_token(p_token);
begin
  return coalesce((
    select jsonb_agg(_public_quiz(q) || jsonb_build_object(
      'attempt', case when a.id is null then null else jsonb_build_object('started_at', a.started_at, 'submitted_at', a.submitted_at) end)
      order by q.created_at desc)
    from quizzes q left join attempts a on a.quiz_id = q.id and a.student_id = s.id
    where q.group_id = s.group_id and s.roll = any(q.assigned_rolls)
      and (q.status = 'live' or a.id is not null)), '[]'::jsonb);
end $$;

-- Finish any attempt whose time is up. Called before every student read or write.
create or replace function public._close_if_due(p_attempt uuid) returns void
language sql security definer set search_path = public as $$
  update attempts a set submitted_at = least(now(), a.deadline), auto = true, updated_at = now()
   where a.id = p_attempt and a.submitted_at is null
     and (now() > a.deadline + interval '20 seconds'
          or exists (select 1 from quizzes q where q.id = a.quiz_id and q.status <> 'live'));
$$;

create or replace function public._attempt_state(p_attempt uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('attempt_id', a.id, 'started_at', a.started_at, 'deadline', a.deadline,
    'submitted_at', a.submitted_at, 'auto', a.auto, 'answers', a.answers, 'marked', a.marked,
    'violations', coalesce((select jsonb_agg(jsonb_build_object('t', v.type, 'at', v.at, 'secs', v.secs) order by v.at)
                            from violations v where v.attempt_id = a.id), '[]'::jsonb),
    'quiz_status', q.status, 'server_now', now())
  from attempts a join quizzes q on q.id = a.quiz_id where a.id = p_attempt;
$$;

create or replace function public.start_attempt(p_token text, p_quiz uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s students := _student_from_token(p_token); q quizzes; a attempts;
begin
  select * into q from quizzes where id = p_quiz and group_id = s.group_id;
  if q.id is null or not (s.roll = any(q.assigned_rolls)) then
    raise exception 'NOT_ASSIGNED' using hint = 'This quiz is not assigned to your roll number.';
  end if;
  select * into a from attempts where quiz_id = q.id and student_id = s.id;
  if a.id is null then
    if q.status <> 'live' then raise exception 'NOT_LIVE' using hint = 'This quiz is not open.'; end if;
    insert into attempts (quiz_id, student_id, deadline)
    values (q.id, s.id, now() + make_interval(mins => q.duration_min))
    on conflict (quiz_id, student_id) do nothing;
    select * into a from attempts where quiz_id = q.id and student_id = s.id;
  end if;
  perform _close_if_due(a.id);
  -- Questions go out without their answers.
  return _attempt_state(a.id) || jsonb_build_object('quiz', _public_quiz(q) || jsonb_build_object('shuffle', q.shuffle,
    'questions', (select jsonb_agg(x - 'answer') from jsonb_array_elements(q.questions) x)));
end $$;

create or replace function public.save_attempt(p_token text, p_quiz uuid, p_answers jsonb, p_marked jsonb,
                                               p_violations jsonb, p_submit boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s students := _student_from_token(p_token); a attempts; q quizzes; v jsonb; n int; p jsonb;
begin
  select * into a from attempts where quiz_id = p_quiz and student_id = s.id;
  if a.id is null then raise exception 'NO_ATTEMPT' using hint = 'Start the quiz first.'; end if;
  select * into q from quizzes where id = a.quiz_id;
  -- Violations are kept even after time is up, so the record is complete.
  for v in select * from jsonb_array_elements(coalesce(p_violations, '[]'::jsonb)) loop
    if v->>'t' in ('tab','copy','cut','paste','menu','drop','fullscreen','screenshot') then
      insert into violations (attempt_id, type, at, secs)
      values (a.id, v->>'t', least(now(), coalesce(to_timestamp((v->>'at')::double precision / 1000), now())),
              nullif(v->>'secs', '')::int);
    end if;
  end loop;
  if a.submitted_at is null and now() <= a.deadline + interval '20 seconds' and q.status = 'live' then
    update attempts set
      answers = coalesce((select jsonb_object_agg(key, value) from jsonb_each(coalesce(p_answers, '{}'::jsonb))
                           where key in (select x->>'id' from jsonb_array_elements(q.questions) x)), '{}'::jsonb),
      marked = coalesce(p_marked, '{}'::jsonb), updated_at = now()
     where id = a.id;
    -- Auto-submit at the proctoring limit.
    p := q.proctor;
    select count(*) into n from violations where attempt_id = a.id;
    if p_submit or (coalesce((p->>'maxV')::int, 0) > 0 and n >= (p->>'maxV')::int) then
      update attempts set submitted_at = least(now(), deadline), auto = not p_submit, updated_at = now() where id = a.id;
    end if;
  end if;
  perform _close_if_due(a.id);
  return _attempt_state(a.id);
end $$;

create or replace function public.student_result(p_token text, p_quiz uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s students := _student_from_token(p_token); q quizzes; a attempts;
begin
  select * into q from quizzes where id = p_quiz and group_id = s.group_id;
  select * into a from attempts where quiz_id = p_quiz and student_id = s.id;
  if q.id is null or a.id is null or not q.released then
    raise exception 'NOT_RELEASED' using hint = 'Your teacher has not released results yet.';
  end if;
  return _attempt_state(a.id) || jsonb_build_object('quiz', _public_quiz(q) || jsonb_build_object('questions', q.questions));
end $$;

create or replace function public.student_logout(p_token text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from student_sessions where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

-- Add questions to the shared bank, skipping exact duplicates (same text, any case).
create or replace function public.import_questions(p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_faculty() then raise exception 'Faculty only.'; end if;
  insert into questions (text, options, answer, topic, difficulty, marks, created_by)
  select r->>'text', r->'options', (r->>'answer')::int, coalesce(nullif(r->>'topic', ''), 'General'),
         coalesce(nullif(r->>'difficulty', ''), 'medium'), coalesce((r->>'marks')::numeric, 1), auth.uid()
    from jsonb_array_elements(p_rows) r
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Students reach the database only through the student_* functions below. Everything else is
-- closed to anonymous visitors and to signed-in accounts that are not approved faculty.
revoke all on all functions in schema public from anon, authenticated, public;
grant execute on function public.student_login(text, text, text)                          to anon, authenticated;
grant execute on function public.student_quizzes(text)                                     to anon, authenticated;
grant execute on function public.start_attempt(text, uuid)                                 to anon, authenticated;
grant execute on function public.save_attempt(text, uuid, jsonb, jsonb, jsonb, boolean)    to anon, authenticated;
grant execute on function public.student_result(text, uuid)                                to anon, authenticated;
grant execute on function public.student_logout(text)                                      to anon, authenticated;
grant execute on function public.register_faculty(text)                                    to authenticated;
grant execute on function public.set_student_pins(jsonb)                                   to authenticated;
grant execute on function public.set_quiz_status(uuid, text)                               to authenticated;
grant execute on function public.import_questions(jsonb)                                   to authenticated;
grant execute on function public.is_faculty()                                              to authenticated;
grant execute on function public.is_admin()                                                to authenticated;

insert into public.groups (id, name) values ('A', 'Group A'), ('B', 'Group B'), ('C', 'Group C');
