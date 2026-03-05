-- ============================================================
-- Replicore Todo Example — Supabase Schema
-- Run this in the Supabase SQL editor before starting the app.
-- ============================================================

-- 1. todos table
create table if not exists public.todos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null,
  is_done     boolean not null default false,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz null          -- soft-delete; NULL = alive
);

-- 2. Keep updated_at current automatically on every UPDATE
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger todos_set_updated_at
  before update on public.todos
  for each row execute function public.set_updated_at();

-- 3. Index used by Replicore's keyset cursor query
--    (WHERE updated_at > $1 OR (updated_at = $1 AND id > $2))
create index if not exists todos_cursor_idx
  on public.todos (updated_at asc, id asc);

-- 4. Row Level Security — every user sees only their own todos
alter table public.todos enable row level security;

create policy "todos: owner access"
  on public.todos
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);
