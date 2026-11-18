# Farm Workforce — deferred feature backlog

## External agricultural contractors — customer-side procurement

**Priority:** Low / deferred. **Status:** Concept only; not scheduled.

**Intent:** When our own farm workforce is overloaded, the farm may hire outside agricultural services or temporary specialist assistance. This models **the farm as the customer**, not the business supplying the services. We are not replicating The Contractor or building a contractor-business simulator.

Potential future workflow:
1. Request a specific farm operation (for example mowing, baling, cultivation or harvesting).
2. Select external operator assistance or a full service with contractor-owned equipment.
3. Agree a rate (hourly, per area or fixed fee).
4. Have the provider undertake the job and depart.
5. Record/pay the service invoice separately from employed-worker payroll.

**Design boundaries:**
- Our regular A–T HelperProfiles roster remains for our farm's workforce; outside providers should not consume these identities merely because they're hired for a job.
- External contractor business bookkeeping, customers, staff management, job marketplace and reputation are **out of scope**.
- The existing `Contractor` *relationship* in workforce member details must not silently turn that member into an external contracting firm.
- Reuse our own dispatch and physical-worker capabilities when sufficiently mature; no dependency on The Contractor.
- Do not implement this until core identity, 3D preview, worker movement and farm-task coordination are reliable.

**Decision:** Recorded 2026-11-18 at the user's request; no implementation started.
