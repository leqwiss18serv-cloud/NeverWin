-- =====================================================================
-- NeverWin · migration 02 (AGENT 1) — применять ПОСЛЕ schema.sql v0.1.1,
-- если схема уже накатывалась раньше. На свежих проектах достаточно
-- одного schema.sql (всё ниже уже включено в него).
-- Порядок: выполнить целиком в SQL Editor.
-- =====================================================================

-- ---------- 1. RLS: чтение своих строк (фикс пустых списков в клиенте) ----------
drop policy if exists prof_read on public.profiles;
create policy prof_read on public.profiles
  for select to authenticated using (auth.uid() = id);

drop policy if exists bank_own_read on public.bank_accounts;
create policy bank_own_read on public.bank_accounts
  for select to authenticated using (auth.uid() = owner_id);

drop policy if exists fr_own_read on public.friendships;
create policy fr_own_read on public.friendships
  for select to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

drop policy if exists msg_own_read on public.messages;
create policy msg_own_read on public.messages
  for select to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user);
drop policy if exists msg_send on public.messages;
create policy msg_send on public.messages
  for insert to authenticated
  with check (
    auth.uid() = from_user and exists (
      select 1 from public.friendships f
      where f.status = 'accepted' and (
        (f.requester_id = auth.uid() and f.addressee_id = to_user) or
        (f.requester_id = to_user and f.addressee_id = auth.uid()))));

drop policy if exists duel_own_read on public.duels;
create policy duel_own_read on public.duels
  for select to authenticated
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

drop policy if exists notice_own_read on public.notices;
create policy notice_own_read on public.notices
  for select to authenticated using (auth.uid() = to_user);
drop policy if exists notice_mark_read on public.notices;
create policy notice_mark_read on public.notices
  for update to authenticated
  using (auth.uid() = to_user) with check (auth.uid() = to_user);

-- ---------- 2. Лидерборд через definer-RPC (view под RLS врёт про банки) ----------
create or replace function public.nw_leaderboard()
returns table(nickname text, total_nc bigint)
language sql security definer set search_path = public as $$
  select p.nickname,
         p.main_balance + coalesce(sum(b.balance), 0)::bigint
  from public.profiles p
  left join public.bank_accounts b on b.owner_id = p.id
  group by p.id, p.nickname, p.main_balance
  order by 2 desc
  limit 10;
$$;

-- ---------- 3. Фикс nw_duel_create: notice теперь ДО return (раньше не доходил) ----------
create or replace function public.nw_duel_create(p_opponent uuid, p_game text, p_bet bigint)
returns setof public.duels
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_me text; v_opp text; v_min bigint; v_did uuid;
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
  insert into public.duels(challenger_id, challenger_nick, opponent_id, opponent_nick, game_id, bet, votes)
    values (v_uid, v_me, p_opponent, v_opp, p_game, p_bet, jsonb_build_object('challenger', p_game))
    returning id into v_did;
  insert into public.notices(to_user, kind, text)
  values (p_opponent, 'duel', v_me||' вызывает тебя на дуэль: '||p_game||', ставка '||p_bet||' NC.');
  return query select * from public.duels where id = v_did;
end $$;

-- ---------- 4. Storage-бакет для фото в мессенджере ----------
insert into storage.buckets(id, name, public)
values ('chat-images', 'chat-images', true)
on conflict (id) do nothing;

drop policy if exists chat_img_read on storage.objects;
create policy chat_img_read on storage.objects
  for select to authenticated using (bucket_id = 'chat-images');
drop policy if exists chat_img_upload on storage.objects;
create policy chat_img_upload on storage.objects
  for insert to authenticated with check (bucket_id = 'chat-images');
