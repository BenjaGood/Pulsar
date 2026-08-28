# Pulsar Community Food Constitution

## Scope and data boundary

- Supabase is exclusively the shared food catalog boundary: OpenNutrition imports, community food contributions, nutrient data, review state, and food evidence images.
- iCloud/local persistence remains the source of truth for profile data, HealthKit samples, workouts, sleep, recovery, personal meals, app settings, and iPhone/Apple Watch synchronization.
- No HealthKit sample, GPS route, workout payload, personal profile, or private meal history may be included in a Supabase request.

## Security and ownership

- The iOS app may contain only the Supabase project URL and publishable/anon key. A service-role key is backend-only.
- Published foods are readable only when their verification status is `imported`, `photo_verified`, or `community_verified`.
- Authenticated contributors may create and edit only their own pending contributions and evidence objects.
- Approval, rejection, publication, and trusted product mutation are backend/service-role operations.
- Evidence paths must be scoped to `user-id/contribution-id/file-name` and use the approved JPEG filenames.

## Product and review behavior

- A contribution contains structured product data, nutrient values, optional evidence images, and a review status.
- New submissions remain pending until reviewed; pending proposals never become public products.
- Submission retries must reuse a stable contribution identifier and be safe to repeat without creating duplicate pending records.
- Nutrient values are validated both on device and by database constraints/functions.

## Verification requirements

- Every community-food change must include focused tests for validation, retry behavior, RLS assumptions, and the public/private visibility boundary.
- Run the narrowest useful iOS build/tests and validate migrations before shipping.
- Review the final diff for accidental HealthKit, workout, profile, iCloud, or WatchConnectivity coupling.
