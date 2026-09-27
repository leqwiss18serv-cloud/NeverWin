-- =====================================================================
-- NeverWin · Supabase schema v0.1.1 (AGENT 1)
-- Применяется в Supabase SQL Editor целиком (проект на паузе -> применить
-- после resume). Вся денежная и игровая логика — SECURITY DEFINER RPC.
-- Клиент никогда не пишет балансы/результаты напрямую (RLS запрещает).
--
-- Стилистика SQL:
-- * таблицы — существительные во мн. числе; RPC — префикс nw_;
-- * все деньги — BIGINT NC, ставки/балансы >= 0 (CHECK);
-- * любое игровое число (мин. ставки, множители, вероятности, лимиты,
--   cooldown, стартовый баланс) — только через таблицу game_config;
-- * деньги двигаются только внутри RPC в одной транзакции
--   (SELECT ... FOR UPDATE), защита от race condition и дабл-спенда;
-- * админы — флаг profiles.is_admin, выдаётся ТОЛЬКО SQL (см. раздел ADMIN).
-- =====================================================================

-- ---------- extensions ----------
create extension if not exists "pgcrypto";

-- ---------- game_config : ВСЁ настраиваемое живёт здесь ----------
create table if not exists public.game_config (
  key   text primary key,
  value jsonb not null
);

insert into public.game_config(key, value) values
  ('start_balance',            '5000'),
  ('min_bet_higher_lower',     '1000'),
  ('min_bet_black_white',      '1500'),
  ('min_bet_dice_even_odd',    '500'),
  ('min_bet_coin_flip',        '500'),
  ('mult_higher_lower',        '2'),
  ('mult_black_white',         '2'),
  ('mult_black_white_green',   '5'),
  ('mult_dice_even_odd',       '2'),
  ('mult_coin_flip',           '2'),
  ('global_x2_mult',           '2'),
  ('global_x2',                'false'),
  ('hl_loss_pct',              '50'),
  ('hl_win_pct',               '45'),
  ('hl_draw_pct',              '5'),
  ('bw_black',                 '25'),
  ('bw_white',                 '25'),
  ('bw_green',                 '2'),
  ('transfer_limit',           '1000000'),
  ('max_bank_accounts',        '10'),
  ('global_cooldown_sec',      '10'),
  ('global_ttl_sec',           '10')
on conflict (key) do nothing;

-- ---------- profiles ----------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  nickname      text unique not null check (nickname ~ '^[A-Za-z0-9_]{3,20}$'),
  main_balance  bigint not null default 5000 check (main_balance >= 0),
  is_admin      boolean not null default false,
  blocked_until timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists idx_profiles_nickname on public.profiles(nickname);
create index if not exists idx_profiles_balance on public.profiles(main_balance desc);

-- ---------- bank_accounts ----------
create table if not exists public.bank_accounts (
  id         uuid primary key default gen_random_uuid(),
  number     text unique not null check (number ~ '^\d{6}$'),
  name       text not null check (char_length(name) between 1 and 30),
  pin_hash   text not null,
  balance    bigint not null default 0 check (balance >= 0),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_bank_owner on public.bank_accounts(owner_id);
create index if not exists idx_bank_number on public.bank_accounts(number);

-- ---------- promo_codes (максимально гибкие) ----------
create table if not exists public.promo_codes (
  id              uuid primary key default gen_random_uuid(),
  code            text unique not null,
  reward          bigint not null check (reward > 0),
  max_global      int not null default 1000 check (max_global >= 0),
  used_global     int not null default 0 check (used_global >= 0),
  max_per_user    int not null default 1 check (max_per_user >= 0),
  active          boolean not null default true,
  valid_from      timestamptz,
  valid_until     timestamptz,
  min_balance     bigint not null default 0,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create table if not exists public.promo_redemptions (
  id         uuid primary key default gen_random_uuid(),
  code_id    uuid not null references public.promo_codes(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(code_id, user_id, created_at)
);
create index if not exists idx_promo_red_user on public.promo_redemptions(code_id, user_id);

insert into public.promo_codes(code, reward, max_global, max_per_user)
values ('WELCOME500', 500, 1000, 1), ('NEVERWIN2026', 1000, 500, 1)
on conflict (code) do nothing;

-- ---------- friendships ----------
create table if not exists public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles(id) on delete cascade,
  requester_nick text not null,
  addressee_id  uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at    timestamptz not null default now(),
  unique(requester_id, addressee_id)
);
create index if not exists idx_fr_addr on public.friendships(addressee_id, status);
create index if not exists idx_fr_req on public.friendships(requester_id, status);

-- ---------- messages ----------
create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null references public.profiles(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  text       text not null default '',
  image_url  text,
  created_at timestamptz not null default now() check (char_length(text) <= 2000)
);
create index if not exists idx_msg_pair on public.messages(from_user, to_user, created_at);

-- ---------- duels (+ votes JSONB для будущего голосования за игру) ----------
create table if not exists public.duels (
  id              uuid primary key default gen_random_uuid(),
  challenger_id   uuid not null references public.profiles(id) on delete cascade,
  challenger_nick text not null,
  opponent_id     uuid not null references public.profiles(id) on delete cascade,
  opponent_nick   text not null,
  game_id         text not null,
  bet             bigint not null check (bet > 0),
  votes           jsonb not null default '{}'::jsonb,
  status          text not null default 'pending' check (status in ('pending','active','finished','declined')),
  winner_id       uuid references public.profiles(id) on delete set null,
  winner_nick     text,
  detail          text,
  created_at      timestamptz not null default now()
);
create index if not exists idx_duels_players on public.duels(challenger_id, opponent_id, status);

-- ---------- notices / global_messages / game_history ----------
create table if not exists public.notices (
  id         uuid primary key default gen_random_uuid(),
  to_user    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null default 'system',
  text       text not null,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_notices_user on public.notices(to_user, created_at desc);

create table if not exists public.global_messages (
  id         uuid primary key default gen_random_uuid(),
  admin_id   uuid references public.profiles(id) on delete set null,
  admin_nick text not null,
  text       text not null check (char_length(text) between 1 and 200),
  created_at timestamptz not null default now()
);

create table if not exists public.game_history (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  game_id    text not null,
  bet        bigint not null,
  payout     bigint not null,
  win        boolean not null,
  draw       boolean not null,
  detail     text,
  created_at timestamptz not null default now()
);

-- ---------- leaderboard view ----------
create or replace view public.v_leaderboard as
select p.nickname,
       p.main_balance + coalesce(sum(b.balance), 0)::bigint as total_nc
from public.profiles p
left join public.bank_accounts b on b.owner_id = p.id
group by p.id, p.nickname, p.main_balance
order by total_nc desc;

-- =====================================================================
-- RLS: всё закрыто по умолчанию, клиент ходит только через RPC.
-- =====================================================================
alter table public.game_config      enable row level security;
alter table public.profiles         enable row level security;
alter table public.bank_accounts    enable row level security;
alter table public.promo_codes      enable row level security;
alter table public.promo_redemptions enable row level security;
alter table public.friendships      enable row level security;
alter table public.messages         enable row level security;
alter table public.duels            enable row level security;
alter table public.notices          enable row level security;
alter table public.global_messages  enable row level security;
alter table public.game_history     enable row level security;

-- чтение конфига и лидерборда — всем аутентифицированным
drop policy if exists cfg_read on public.game_config;
create policy cfg_read on public.game_config for select to authenticated using (true);
drop policy if exists prof_read on public.profiles;
create policy prof_read on public.profiles for select to authenticated using (true);
-- чтение своих счетов / входящих переводов получателю не нужно: всё через RPC
-- глобальные сообщения читают все
drop policy if exists gm_read on public.global_messages;
create policy gm_read on public.global_messages for select to authenticated using (true);
-- прямые insert/update/delete клиента запрещены (политик нет = deny).
-- profiles создаются только триггером/RPC (service_role / security definer).

-- =====================================================================
-- Helpers
-- =====================================================================
create or replace function public.nw_cfg_int(p_key text)
returns bigint language sql stable as
$$ select coalesce((select (value::text)::bigint from public.game_config where key = p_key), 0) $$;

create or replace function public.nw_cfg_bool(p_key text)
returns boolean language sql stable as
$$ select coalesce((select (value::text)::boolean from public.game_config where key = p_key), false) $$;

create or replace function public.nw_is_admin(p_uid uuid)
returns boolean language sql stable as
$$ select coalesce((select is_admin from public.profiles where id = p_uid), false) $$;

create or replace function public.nw_assert_open(p_uid uuid)
returns void language plpgsql as $$
declare v_until timestamptz;
begin
  select blocked_until into v_until from public.profiles where id = p_uid;
  if v_until is not null and v_until > now() then
    raise exception 'blocked_until_%', v_until using errcode = 'P0001';
  end if;
end $$;

-- =====================================================================
-- REGISTRATION helper: создаёт профиль со стартовым балансом (идемпотентно)
-- =====================================================================
create or replace function public.nw_ensure_profile(p_nickname text)
returns setof public.profiles
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_nickname !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'bad_nickname'; end if;
  if exists (select 1 from public.profiles where nickname = p_nickname and id <> v_uid) then
    raise exception 'nickname_taken';
  end if;
  insert into public.profiles(id, nickname, main_balance)
  values (v_uid, p_nickname, public.nw_cfg_int('start_balance'))
  on conflict (id) do update set nickname = excluded.nickname;
  return query select * from public.profiles where id = v_uid;
end $$;

-- =====================================================================
-- GAME: единый серверный движок. Вероятности из game_config.
-- higher_lower 50/45/5 (loss/win/draw), black_white 25/25/2 (green x5, <8%),
-- dice_even_odd, coin_flip. Выигрыш: bet*mult[*global_x2_mult].
-- =====================================================================
create or replace function public.nw_play(p_game text, p_choice text, p_bet bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_bal bigint;
  v_min bigint;
  v_mult bigint := 2;
  v_gx boolean;
  v_gx_mult bigint;
  v_payout bigint := 0;
  v_win boolean := false;
  v_draw boolean := false;
  v_detail text := '';
  v_data jsonb := '{}'::jsonb;
  v_first int; v_second int; v_roll int;
  v_loss int; v_winp int;
  v_pick int; v_black int; v_white int; v_green int;
  v_d1 int; v_d2 int; v_sum int;
  v_heads boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  if p_bet is null or p_bet <= 0 then raise exception 'bad_bet'; end if;

  select main_balance into v_bal from public.profiles where id = v_uid for update;
  if v_bal is null then raise exception 'no_profile'; end if;

  v_min := public.nw_cfg_int('min_bet_' || p_game);
  if v_min <= 0 then raise exception 'unknown_game'; end if;
  if p_bet < v_min then raise exception 'min_bet_%', v_min; end if;
  if v_bal < p_bet then raise exception 'insufficient_funds'; end if;

  v_gx := public.nw_cfg_bool('global_x2');
  v_gx_mult := public.nw_cfg_int('global_x2_mult');

  if p_game = 'higher_lower' then
    if p_choice not in ('higher','lower') then raise exception 'bad_choice'; end if;
    v_first := 1 + floor(random()*200)::int;
    v_loss := public.nw_cfg_int('hl_loss_pct')::int;
    v_winp := public.nw_cfg_int('hl_win_pct')::int;
    v_roll := floor(random()*100)::int;
    if v_roll < v_loss then
      v_win := false;
      v_second := case when p_choice='higher'
        then (case when v_first<=1 then v_first else 1+floor(random()*(v_first-1))::int end)
        else (case when v_first>=200 then v_first else v_first+1+floor(random()*(200-v_first))::int end) end;
    elsif v_roll < v_loss + v_winp then
      v_win := true;
      v_second := case when p_choice='higher'
        then (case when v_first>=200 then v_first else v_first+1+floor(random()*(200-v_first))::int end)
        else (case when v_first<=1 then v_first else 1+floor(random()*(v_first-1))::int end) end;
    else
      v_second := v_first;
    end if;
    if v_second = v_first then v_draw := true; v_win := false; end if;
    v_mult := public.nw_cfg_int('mult_higher_lower');
    v_data := jsonb_build_object('first', v_first, 'second', v_second);
    v_detail := case when v_draw then 'Ничья: '||v_first||'. Ставка возвращена.'
      when v_win then 'Победа! '||v_first||' → '||v_second
      else 'Поражение. '||v_first||' → '||v_second end;

  elsif p_game = 'black_white' then
    if p_choice not in ('black','white') then raise exception 'bad_choice'; end if;
    v_black := public.nw_cfg_int('bw_black')::int;
    v_white := public.nw_cfg_int('bw_white')::int;
    v_green := public.nw_cfg_int('bw_green')::int;
    v_pick := floor(random()*(v_black+v_white+v_green))::int;
    if v_pick < v_green then
      v_win := true; v_mult := public.nw_cfg_int('mult_black_white_green');
      v_data := '{"color":"green"}'; v_detail := 'ЗЕЛЁНЫЙ! Выигрыш x'||v_mult||'.';
    elsif v_pick < v_green + v_black then
      v_win := (p_choice = 'black'); v_mult := public.nw_cfg_int('mult_black_white');
      v_data := '{"color":"black"}';
      v_detail := case when v_win then 'Выпало: ЧЁРНОЕ — победа!' else 'Выпало: ЧЁРНОЕ — проигрыш.' end;
    else
      v_win := (p_choice = 'white'); v_mult := public.nw_cfg_int('mult_black_white');
      v_data := '{"color":"white"}';
      v_detail := case when v_win then 'Выпало: БЕЛОЕ — победа!' else 'Выпало: БЕЛОЕ — проигрыш.' end;
    end if;

  elsif p_game = 'dice_even_odd' then
    if p_choice not in ('even','odd') then raise exception 'bad_choice'; end if;
    v_d1 := 1+floor(random()*6)::int; v_d2 := 1+floor(random()*6)::int; v_sum := v_d1+v_d2;
    v_win := ((v_sum % 2 = 0) = (p_choice='even'));
    v_mult := public.nw_cfg_int('mult_dice_even_odd');
    v_data := jsonb_build_object('d1',v_d1,'d2',v_d2,'sum',v_sum);
    v_detail := 'Кубики: '||v_d1||'+'||v_d2||'='||v_sum||case when v_win then ' — победа!' else ' — проигрыш.' end;

  elsif p_game = 'coin_flip' then
    if p_choice not in ('heads','tails') then raise exception 'bad_choice'; end if;
    v_heads := random() < 0.5;
    v_win := ((p_choice='heads') = v_heads);
    v_mult := public.nw_cfg_int('mult_coin_flip');
    v_data := jsonb_build_object('side', case when v_heads then 'heads' else 'tails' end);
    v_detail := case when v_heads then 'Выпало: ОРЁЛ' else 'Выпало: РЕШКА' end
      || case when v_win then ' — победа!' else ' — проигрыш.' end;
  else
    raise exception 'unknown_game';
  end if;

  if v_draw then v_payout := p_bet;
  elsif v_win then v_payout := p_bet * v_mult * (case when v_gx then v_gx_mult else 1 end);
  else v_payout := 0; end if;

  update public.profiles set main_balance = main_balance - p_bet + v_payout where id = v_uid;
  insert into public.game_history(user_id, game_id, bet, payout, win, draw, detail)
  values (v_uid, p_game, p_bet, v_payout, v_win, v_draw, v_detail);

  return jsonb_build_object('payout', v_payout, 'win', v_win, 'draw', v_draw,
    'detail', v_detail, 'data', v_data, 'global_x2', (v_gx and v_win));
end $$;

-- =====================================================================
-- BANK RPCs
-- =====================================================================
create or replace function public.nw_bank_create(p_name text, p_pin text)
returns setof public.bank_accounts
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_num text; v_cnt int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  if char_length(p_name) not between 1 and 30 then raise exception 'bad_name'; end if;
  if p_pin !~ '^\d{4}$' then raise exception 'bad_pin'; end if;
  select count(*) into v_cnt from public.bank_accounts where owner_id = v_uid;
  if v_cnt >= public.nw_cfg_int('max_bank_accounts') then raise exception 'account_limit'; end if;
  loop
    v_num := lpad((100000 + floor(random()*900000)::int)::text, 6, '0');
    exit when not exists (select 1 from public.bank_accounts where number = v_num);
  end loop;
  return query insert into public.bank_accounts(number, name, pin_hash, owner_id)
    values (v_num, p_name, encode(digest('pin::'||p_pin, 'sha256'), 'hex'), v_uid)
    returning *;
end $$;

create or replace function public.nw_bank_deposit(p_account uuid, p_amount bigint)
returns setof public.bank_accounts
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_bal bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  select main_balance into v_bal from public.profiles where id = v_uid for update;
  if v_bal < p_amount then raise exception 'insufficient_funds'; end if;
  update public.profiles set main_balance = main_balance - p_amount where id = v_uid;
  return query update public.bank_accounts set balance = balance + p_amount
    where id = p_account and owner_id = v_uid returning *;
end $$;

create or replace function public.nw_bank_withdraw(p_account uuid, p_amount bigint)
returns setof public.bank_accounts
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row public.bank_accounts;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  select * into v_row from public.bank_accounts where id = p_account and owner_id = v_uid for update;
  if v_row.id is null then raise exception 'no_account'; end if;
  if v_row.balance < p_amount then raise exception 'insufficient_funds'; end if;
  update public.bank_accounts set balance = balance - p_amount where id = p_account;
  update public.profiles set main_balance = main_balance + p_amount where id = v_uid;
  return query select * from public.bank_accounts where id = p_account;
end $$;

create or replace function public.nw_bank_transfer(p_from uuid, p_target_number text, p_amount bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_from public.bank_accounts; v_to public.bank_accounts;
  v_me text; v_lim bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  if p_target_number !~ '^\d{6}$' then raise exception 'bad_target'; end if;
  v_lim := public.nw_cfg_int('transfer_limit');
  if p_amount > v_lim then raise exception 'transfer_limit'; end if;
  select * into v_from from public.bank_accounts where id = p_from and owner_id = v_uid for update;
  if v_from.id is null then raise exception 'no_account'; end if;
  select * into v_to from public.bank_accounts where number = p_target_number for update;
  if v_to.id is null then raise exception 'target_not_found'; end if;
  if v_to.id = v_from.id then raise exception 'same_account'; end if;
  if v_from.balance < p_amount then raise exception 'insufficient_funds'; end if;
  update public.bank_accounts set balance = balance - p_amount where id = v_from.id;
  update public.bank_accounts set balance = balance + p_amount where id = v_to.id;
  select nickname into v_me from public.profiles where id = v_uid;
  insert into public.notices(to_user, kind, text)
  values (v_to.owner_id, 'transfer',
    'Игрок '||v_me||' перевёл на ваш счёт «'||v_to.name||'» '||p_amount||' NC.');
end $$;

-- =====================================================================
-- PROMO redeem (атомарно, лимиты global/per-user, срок действия)
-- =====================================================================
create or replace function public.nw_redeem_promo(p_code text)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_p public.promo_codes; v_mine int; v_bal bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  select * into v_p from public.promo_codes where code = upper(trim(p_code)) for update;
  if v_p.id is null then raise exception 'promo_not_found'; end if;
  if not v_p.active then raise exception 'promo_inactive'; end if;
  if v_p.valid_until is not null and v_p.valid_until < now() then raise exception 'promo_expired'; end if;
  if v_p.valid_from is not null and v_p.valid_from > now() then raise exception 'promo_inactive'; end if;
  if v_p.used_global >= v_p.max_global then raise exception 'promo_exhausted'; end if;
  select count(*) into v_mine from public.promo_redemptions where code_id = v_p.id and user_id = v_uid;
  if v_mine >= v_p.max_per_user then raise exception 'promo_used'; end if;
  select main_balance into v_bal from public.profiles where id = v_uid;
  if v_bal < v_p.min_balance then raise exception 'promo_min_balance'; end if;
  update public.promo_codes set used_global = used_global + 1 where id = v_p.id;
  insert into public.promo_redemptions(code_id, user_id) values (v_p.id, v_uid);
  update public.profiles set main_balance = main_balance + v_p.reward where id = v_uid;
  return v_p.reward;
end $$;

-- =====================================================================
-- FRIENDS / MESSENGER helpers
-- =====================================================================
create or replace function public.nw_friend_request(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_tid uuid; v_me text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  select id into v_tid from public.profiles where nickname = p_nickname;
  if v_tid is null then raise exception 'user_not_found'; end if;
  if v_tid = v_uid then raise exception 'self_request'; end if;
  if exists (select 1 from public.friendships
      where ((requester_id=v_uid and addressee_id=v_tid) or (requester_id=v_tid and addressee_id=v_uid))
        and status in ('pending','accepted')) then raise exception 'already_exists'; end if;
  select nickname into v_me from public.profiles where id = v_uid;
  insert into public.friendships(requester_id, requester_nick, addressee_id)
  values (v_uid, v_me, v_tid);
  insert into public.notices(to_user, kind, text)
  values (v_tid, 'friend', 'Новая заявка в друзья от '||v_me||'.');
end $$;

create or replace function public.nw_friend_respond(p_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_r public.friendships; v_me text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_r from public.friendships where id = p_id and addressee_id = v_uid for update;
  if v_r.id is null then raise exception 'request_not_found'; end if;
  update public.friendships set status = case when p_accept then 'accepted' else 'declined' end where id = p_id;
  select nickname into v_me from public.profiles where id = v_uid;
  insert into public.notices(to_user, kind, text)
  values (v_r.requester_id, 'friend',
    case when p_accept then v_me||' принял вашу заявку в друзья.'
         else v_me||' отклонил вашу заявку в друзья.' end);
end $$;

create or replace function public.nw_friends()
returns table(user_id uuid, nickname text)
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  return query
  select case when f.requester_id = v_uid then f.addressee_id else f.requester_id end,
         p.nickname
  from public.friendships f join public.profiles p
    on p.id = case when f.requester_id = v_uid then f.addressee_id else f.requester_id end
  where f.status = 'accepted' and (f.requester_id = v_uid or f.addressee_id = v_uid);
end $$;

create or replace function public.nw_friend_remove(p_friend uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  delete from public.friendships
  where status='accepted' and ((requester_id=v_uid and addressee_id=p_friend)
    or (requester_id=p_friend and addressee_id=v_uid));
end $$;

-- =====================================================================
-- DUELS: head-to-head, обе ставки списываются атомарно, победитель забирает
-- пот x2 (x2 при global_x2). Ничья (зелёное/совпадение) — возврат.
-- =====================================================================
create or replace function public.nw_duel_create(p_opponent uuid, p_game text, p_bet bigint)
returns setof public.duels
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_me text; v_opp text; v_min bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  select nickname into v_opp from public.profiles where id = p_opponent;
  if v_opp is null then raise exception 'user_not_found'; end if;
  if not exists (select 1 from public.friendships
      where status='accepted' and ((requester_id=v_uid and addressee_id=p_opponent)
        or (requester_id=p_opponent and addressee_id=v_uid))) then
    raise exception 'not_friends';
  end if;
  v_min := public.nw_cfg_int('min_bet_' || p_game);
  if v_min <= 0 then raise exception 'unknown_game'; end if;
  if p_bet < v_min then raise exception 'min_bet_%', v_min; end if;
  select nickname into v_me from public.profiles where id = v_uid;
  return query insert into public.duels(challenger_id, challenger_nick, opponent_id, opponent_nick, game_id, bet, votes)
    values (v_uid, v_me, p_opponent, v_opp, p_game, p_bet, jsonb_build_object('challenger', p_game))
    returning *;
  insert into public.notices(to_user, kind, text)
  values (p_opponent, 'duel', v_me||' вызывает тебя на дуэль: '||p_game||', ставка '||p_bet||' NC.');
end $$;

create or replace function public.nw_duel_respond(p_id uuid, p_accept boolean)
returns setof public.duels
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_d public.duels;
  v_ch_bal bigint; v_op_bal bigint;
  v_gx boolean; v_gx_mult bigint;
  v_pot bigint; v_ch_win boolean; v_draw boolean := false; v_det text := '';
  v_n int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform public.nw_assert_open(v_uid);
  select * into v_d from public.duels where id = p_id and status='pending' for update;
  if v_d.id is null then raise exception 'duel_not_found'; end if;
  if v_d.opponent_id <> v_uid then raise exception 'not_your_duel'; end if;
  if not p_accept then
    update public.duels set status='declined' where id = p_id;
    insert into public.notices(to_user, kind, text)
    values (v_d.challenger_id, 'duel', (select nickname from public.profiles where id=v_uid)||' отклонил дуэль.');
    return query select * from public.duels where id = p_id;
    return;
  end if;
  select main_balance into v_ch_bal from public.profiles where id = v_d.challenger_id for update;
  select main_balance into v_op_bal from public.profiles where id = v_uid for update;
  if v_ch_bal < v_d.bet or v_op_bal < v_d.bet then raise exception 'insufficient_funds'; end if;
  v_gx := public.nw_cfg_bool('global_x2');
  v_gx_mult := public.nw_cfg_int('global_x2_mult');

  if v_d.game_id = 'coin_flip' then
    v_ch_win := random() < 0.5; v_det := case when v_ch_win then 'ОРЁЛ' else 'РЕШКА' end;
  elsif v_d.game_id = 'dice_even_odd' then
    v_n := (1+floor(random()*6)::int) + (1+floor(random()*6)::int);
    v_ch_win := (v_n % 2 = 0); v_det := 'Сумма '||v_n;
  elsif v_d.game_id = 'black_white' then
    v_n := floor(random()*52)::int;
    if v_n < 2 then v_draw := true; v_det := 'ЗЕЛЁНЫЙ — ничья'; else v_ch_win := v_n < 27; end if;
  else
    v_ch_win := random() < 0.5;
    v_det := case when v_ch_win then 'Больше' else 'Меньше' end;
  end if;

  update public.profiles set main_balance = main_balance - v_d.bet where id = v_d.challenger_id;
  update public.profiles set main_balance = main_balance - v_d.bet where id = v_uid;
  if v_draw then
    update public.profiles set main_balance = main_balance + v_d.bet where id = v_d.challenger_id;
    update public.profiles set main_balance = main_balance + v_d.bet where id = v_uid;
    update public.duels set status='finished', detail=v_det where id = p_id;
  else
    v_pot := v_d.bet * 2 * (case when v_gx then v_gx_mult else 1 end);
    if v_ch_win then
      update public.profiles set main_balance = main_balance + v_pot where id = v_d.challenger_id;
      update public.duels set status='finished', winner_id=v_d.challenger_id,
        winner_nick=v_d.challenger_nick, detail=v_det where id = p_id;
    else
      update public.profiles set main_balance = main_balance + v_pot where id = v_uid;
      update public.duels set status='finished', winner_id=v_uid,
        winner_nick=(select nickname from public.profiles where id=v_uid), detail=v_det where id = p_id;
    end if;
  end if;
  insert into public.notices(to_user, kind, text)
  values (v_d.challenger_id, 'duel', 'Дуэль завершена: '||v_det||'.');
  return query select * from public.duels where id = p_id;
end $$;

-- =====================================================================
-- ADMIN RPCs (is_admin проверяется внутри; флаг выдаётся только SQL)
-- =====================================================================
create or replace function public.nw_admin_block(p_nickname text, p_until timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.nw_is_admin(auth.uid()) then raise exception 'not_admin'; end if;
  update public.profiles set blocked_until = p_until where nickname = p_nickname;
  if not found then raise exception 'user_not_found'; end if;
end $$;

create or replace function public.nw_admin_unblock(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.nw_is_admin(auth.uid()) then raise exception 'not_admin'; end if;
  update public.profiles set blocked_until = null where nickname = p_nickname;
  if not found then raise exception 'user_not_found'; end if;
end $$;

create or replace function public.nw_admin_grant(p_nickname text, p_amount bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.nw_is_admin(auth.uid()) then raise exception 'not_admin'; end if;
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  update public.profiles set main_balance = main_balance + p_amount where nickname = p_nickname;
  if not found then raise exception 'user_not_found'; end if;
end $$;

create or replace function public.nw_admin_take(p_nickname text, p_amount bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.nw_is_admin(auth.uid()) then raise exception 'not_admin'; end if;
  if p_amount <= 0 then raise exception 'bad_amount'; end if;
  update public.profiles set main_balance = greatest(0, main_balance - p_amount) where nickname = p_nickname;
  if not found then raise exception 'user_not_found'; end if;
end $$;

create or replace function public.nw_admin_global(p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_me text; v_cd int; v_last timestamptz;
begin
  if not public.nw_is_admin(v_uid) then raise exception 'not_admin'; end if;
  if char_length(trim(p_text)) not between 1 and 200 then raise exception 'bad_text'; end if;
  v_cd := public.nw_cfg_int('global_cooldown_sec')::int;
  select max(created_at) into v_last from public.global_messages where admin_id = v_uid;
  if v_last is not null and extract(epoch from (now() - v_last)) < v_cd then
    raise exception 'cooldown_%', v_cd;
  end if;
  select nickname into v_me from public.profiles where id = v_uid;
  insert into public.global_messages(admin_id, admin_nick, text) values (v_uid, v_me, trim(p_text));
end $$;

create or replace function public.nw_admin_set_param(p_key text, p_value jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.nw_is_admin(auth.uid()) then raise exception 'not_admin'; end if;
  update public.game_config set value = p_value where key = p_key;
  if not found then raise exception 'unknown_param'; end if;
end $$;

-- =====================================================================
-- ADMIN via SQL (выполнять вручную в SQL Editor):
--
--   -- выдать админа:
--   update public.profiles set is_admin = true where nickname = 'Alice';
--   -- снять админа:
--   update public.profiles set is_admin = false where nickname = 'Bob';
--   -- забанить навсегда / до даты / разбанить:
--   update public.profiles set blocked_until = '2099-01-01' where nickname = 'X';
--   update public.profiles set blocked_until = null where nickname = 'X';
--   -- выдать/списать NC:
--   update public.profiles set main_balance = main_balance + 10000 where nickname = 'X';
--   -- поменять ставку/множитель/вероятность без пересборки APK:
--   update public.game_config set value = '2000' where key = 'min_bet_higher_lower';
--   update public.game_config set value = 'true' where key = 'global_x2';
--   -- гибкий промокод (награда, лимиты, срок, мин. баланс, metadata):
--   insert into public.promo_codes(code, reward, max_global, max_per_user, valid_until, min_balance, metadata)
--   values ('TURBO99', 2500, 100, 2, now() + interval '7 days', 0, '{"event":"turbo"}');
-- =====================================================================
