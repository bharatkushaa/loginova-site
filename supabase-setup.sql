-- Run this once in Supabase: SQL Editor > New query > paste > Run

create table profiles(
  id uuid primary key references auth.users on delete cascade,
  name text, phone text, email text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz default now()
);

create table bookings(
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  pickup text not null, drop_loc text not null, cargo text not null,
  weight text, truck text, pickup_date date,
  status text not null default 'pending'
    check (status in ('pending','confirmed','in_transit','delivered','cancelled')),
  price numeric, vehicle_no text, admin_note text,
  created_at timestamptz default now()
);

alter table profiles enable row level security;
alter table bookings enable row level security;

create function is_admin() returns boolean
language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;

-- every new signup becomes a customer automatically
create function handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,name,phone,email)
  values(new.id,new.raw_user_meta_data->>'name',new.raw_user_meta_data->>'phone',new.email);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function handle_new_user();

-- profiles: read own (admin reads all). Nobody can edit roles from the website.
create policy "read profile" on profiles for select using (id=auth.uid() or is_admin());

-- bookings
create policy "read bookings" on bookings for select using (user_id=auth.uid() or is_admin());
create policy "customer creates" on bookings for insert
  with check (user_id=auth.uid() and status='pending' and price is null);
create policy "customer cancels pending" on bookings for update
  using (user_id=auth.uid() and status='pending')
  with check (user_id=auth.uid() and status='cancelled');
create policy "admin updates" on bookings for update using (is_admin()) with check (is_admin());
create policy "admin deletes" on bookings for delete using (is_admin());

-- AFTER you sign up on the website with your own email, make yourself admin:
-- update profiles set role='admin' where email='your-email@example.com';
