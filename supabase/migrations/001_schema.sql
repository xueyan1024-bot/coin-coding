-- Coin Coding 数据库 schema
-- 用法：Supabase Dashboard → SQL Editor → New query → 粘贴全部 → Run

-- 用户档案（每人一行，挂在 auth.users 上）
create table if not exists public.profiles (
  id              uuid references auth.users on delete cascade primary key,
  github_username text        not null,
  github_avatar   text,
  coin_name       text        not null default 'coins',
  coin_image_url  text,
  total_coins     bigint      not null default 0,
  created_at      timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "read_all"   on public.profiles for select using (true);
create policy "own_insert" on public.profiles for insert with check (auth.uid() = id);
create policy "own_update" on public.profiles for update using (auth.uid() = id);

-- 安全加分（由 Edge Function 用 service_role 调用，绕过 RLS）
create or replace function public.add_coins(p_user_id uuid, p_amount integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set total_coins = total_coins + p_amount where id = p_user_id;
end;
$$;

-- 新用户注册时自动建档案
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, github_username, github_avatar)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'user_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
