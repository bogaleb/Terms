# Security model

Supabase enforces tenancy via row-level security backed by helper functions defined in `supabase/schema/supabase_functions.sql`.

## Roles

`membership_role` enum defines four roles:

| role   | capabilities |
| ------ | ------------ |
| owner  | manage organizations, businesses, books, invites, entries |
| admin  | manage businesses, books, invites, entries |
| member | manage books and entries |
| viewer | read only |

## Helper functions

- `user_has_org_role(org_id uuid, roles text[])` – security definer function to check membership regardless of RLS.
- `user_has_business_role(business_id uuid, roles text[])` – business membership lookup.
- `user_is_entry_owner(entry_id uuid)` – allows entry creators to edit their own entries even if they only have `member` access.
- `organization_has_members(target_org uuid)` / `business_has_members(target_business uuid)` – allow the first owner membership to be created from the onboarding flow.

## Policy overview

| table                 | select                                   | insert                                                                                  | update                                                      | delete                                 |
| --------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------- | --------------------------------------- |
| `profiles`            | user can see/update their own profile    | user can insert row for themselves                                                      | same as select                                              | n/a                                     |
| `organizations`       | members + creator have access            | authenticated user can create new organization                                          | owners & admins                                             | owners only                             |
| `organization_members`| members can view roster                  | owners/admins can invite; first owner allowed without existing memberships              | owners/admins                                               | owners only                             |
| `businesses`          | org members                              | owners/admins                                                                            | owners/admins                                              | owners only                             |
| `business_members`    | org members                              | owners/admins; bootstrap if business has no members and org owner is inserting themselves | owners/admins                                               | owners only                             |
| `books`               | business members                         | owners/admins                                                                            | owners/admins                                              | owners only                             |
| `entries`             | business members                         | owners/admins/members                                                                    | owners/admins or entry creator via `user_is_entry_owner`    | owners/admins or entry creator          |
| `invites`             | owners/admins                            | owners/admins                                                                            | owners/admins                                              | owners only                             |

All policies grant the Supabase service role full access (`auth.role() = 'service_role'`).

## Testing checklist

1. Owner can create org, business, and default book; member cannot create businesses.
2. Viewer can read entries but cannot insert or update them.
3. Entry creator with `member` role can edit their own entry.
4. Invite table only accessible by owners/admins (select + insert).

These scenarios can be expressed with the Supabase client in a Jest environment or Supabase SQL tests.

## Invite acceptance

The mobile client calls the `accept_invite(raw_token text)` security-definer RPC.
It hashes the incoming token, validates expiry, inserts/upgrades organization and business memberships, then stamps `accepted_at`.
The RPC is defined in `supabase/schema/supabase_functions.sql` and respects the same role matrix as the direct table policies.
