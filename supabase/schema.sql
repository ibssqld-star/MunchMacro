-- ============================================================
-- MacroMunch — full database setup
-- Run this once in the Supabase SQL Editor of the NEW project.
-- Safe to re-run: everything is guarded with if-not-exists / drop-if-exists.
-- ============================================================

-- ---------- 1. TABLES ----------

create table if not exists profile (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  display_name  text,
  goal_cal      int not null default 2000,
  goal_protein  int not null default 150,
  goal_carbs    int not null default 220,
  goal_fat      int not null default 65,
  goal_fiber    int not null default 30,
  goal_water    int not null default 8,
  treats        int not null default 0,            -- reward currency (was "bamboo")
  level         int not null default 1,
  xp            int not null default 0,
  energy        int not null default 60,
  active_pet    text not null default 'momo',
  unlocked      jsonb not null default '{"momo":true,"bao":false,"nova":false}'::jsonb,
  updated_at    timestamptz not null default now()
);

create table if not exists food_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null default current_date,
  name        text not null,
  emoji       text not null default '🍽️',
  meal        text not null default 'Snack'
                check (meal in ('Breakfast','Lunch','Dinner','Snack','Meal prep')),
  cal         int not null default 0 check (cal     >= 0),
  protein     int not null default 0 check (protein >= 0),
  carbs       int not null default 0 check (carbs   >= 0),
  fat         int not null default 0 check (fat     >= 0),
  fiber       int not null default 0 check (fiber   >= 0),
  prep_id     uuid,                                -- set when logged from a meal-prep serving
  created_at  timestamptz not null default now()
);

create table if not exists daily_state (
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null default current_date,
  water       int  not null default 0 check (water >= 0),
  claimed     jsonb not null default '{}'::jsonb,  -- goals already paid out today
  primary key (user_id, logged_on)
);

create table if not exists meal_preps (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  emoji        text not null default '🍱',
  servings     int  not null check (servings > 0),
  consumed     int  not null default 0 check (consumed >= 0),
  per_cal      int  not null default 0,
  per_protein  int  not null default 0,
  per_carbs    int  not null default 0,
  per_fat      int  not null default 0,
  per_fiber    int  not null default 0,
  ingredients  jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default now(),
  constraint consumed_within_servings check (consumed <= servings)
);

create table if not exists shopping_items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  cat        text not null default 'Other'
               check (cat in ('Produce','Protein','Dairy','Pantry','Snacks','Other')),
  done       boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists body_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kg          numeric(5,1) not null check (kg > 0 and kg < 500),
  measured_at timestamptz not null default now()
);

create table if not exists user_foods (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references auth.users(id) on delete cascade,
  name     text not null,
  emoji    text not null default '🍽️',
  unit     text not null default 'g',
  base     numeric not null default 100 check (base > 0),
  cal      int not null default 0,
  protein  int not null default 0,
  carbs    int not null default 0,
  fat      int not null default 0,
  fiber    int not null default 0,
  starred  boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

-- ---------- 2. INDEXES ----------
create index if not exists food_log_user_day_idx    on food_log (user_id, logged_on desc);
create index if not exists food_log_prep_idx        on food_log (prep_id) where prep_id is not null;
create index if not exists meal_preps_user_idx      on meal_preps (user_id, created_at desc);
create index if not exists shopping_user_idx        on shopping_items (user_id, done, created_at desc);
create index if not exists body_log_user_idx        on body_log (user_id, measured_at desc);
create index if not exists user_foods_user_idx      on user_foods (user_id, starred desc);

-- ---------- 3. ROW LEVEL SECURITY ----------
-- Every table: a user can only ever touch their own rows.

alter table profile        enable row level security;
alter table food_log       enable row level security;
alter table daily_state    enable row level security;
alter table meal_preps     enable row level security;
alter table shopping_items enable row level security;
alter table body_log       enable row level security;
alter table user_foods     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['profile','food_log','daily_state','meal_preps','shopping_items','body_log','user_foods']
  loop
    execute format('drop policy if exists "own rows select" on %I', t);
    execute format('drop policy if exists "own rows insert" on %I', t);
    execute format('drop policy if exists "own rows update" on %I', t);
    execute format('drop policy if exists "own rows delete" on %I', t);

    execute format('create policy "own rows select" on %I for select using (auth.uid() = user_id)', t);
    execute format('create policy "own rows insert" on %I for insert with check (auth.uid() = user_id)', t);
    execute format('create policy "own rows update" on %I for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
    execute format('create policy "own rows delete" on %I for delete using (auth.uid() = user_id)', t);
  end loop;
end $$;

-- ---------- 4. AUTO-CREATE A PROFILE ON SIGNUP ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profile (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 5. KEEP consumed IN SYNC WHEN A PREP SERVING IS DELETED ----------
-- Deleting the food_log row for a prep serving should free that serving again.
create or replace function public.on_food_log_delete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.prep_id is not null then
    update meal_preps
       set consumed = greatest(0, consumed - 1)
     where id = old.prep_id and user_id = old.user_id;
  end if;
  return old;
end $$;

drop trigger if exists food_log_after_delete on food_log;
create trigger food_log_after_delete
  after delete on food_log
  for each row execute function public.on_food_log_delete();

-- ---------- 6. TODAY'S TOTALS (handy read for the dashboard) ----------
create or replace view today_totals
with (security_invoker = true) as
select
  user_id,
  logged_on,
  coalesce(sum(cal),0)::int     as cal,
  coalesce(sum(protein),0)::int as protein,
  coalesce(sum(carbs),0)::int   as carbs,
  coalesce(sum(fat),0)::int     as fat,
  coalesce(sum(fiber),0)::int   as fiber
from food_log
group by user_id, logged_on;

-- ---------- 7. ATOMIC TREAT SPEND (prevents double-feeding) ----------
create or replace function public.spend_treats(amount int)
returns profile
language plpgsql
security definer set search_path = public
as $$
declare row profile;
begin
  update profile
     set treats = treats - amount,
         updated_at = now()
   where user_id = auth.uid() and treats >= amount
  returning * into row;

  if row is null then
    raise exception 'not enough treats';
  end if;
  return row;
end $$;

-- ---------- 8. AWARD TREATS ONCE PER GOAL PER DAY ----------
-- Call with the goal key ('cal','protein',…) and the payout. Returns treats awarded (0 if already claimed).
create or replace function public.claim_goal(goal_key text, payout int)
returns int
language plpgsql
security definer set search_path = public
as $$
declare already boolean;
begin
  insert into daily_state (user_id, logged_on)
  values (auth.uid(), current_date)
  on conflict (user_id, logged_on) do nothing;

  select coalesce((claimed ->> goal_key)::boolean, false) into already
    from daily_state
   where user_id = auth.uid() and logged_on = current_date
     for update;

  if already then
    return 0;
  end if;

  update daily_state
     set claimed = claimed || jsonb_build_object(goal_key, true)
   where user_id = auth.uid() and logged_on = current_date;

  update profile
     set treats = treats + payout, updated_at = now()
   where user_id = auth.uid();

  return payout;
end $$;
