# Fix 3: React render loops and runaway requests

Builder: any React/Vite app from Lovable, Bolt, Replit, v0, Base44.

## Symptoms

| What you see | What it usually means |
|---|---|
| `Uncaught Error: Maximum update depth exceeded` (React error #185 in production builds) | A `useEffect` sets state that is in its own dependency array, or a dependency is a new object/array/function on every render |
| `Too many re-renders. React limits the number of renders to prevent an infinite loop.` | `setState(...)` is called directly in the component body or in JSX, not inside an event handler or effect |
| Spinner never stops, CPU fan spins up, tab freezes | Same loop, but the state change happens to be idempotent so React does not throw; it just re-renders forever |
| Network tab shows the same Supabase request firing hundreds of times | An effect with a fetch depends on something that changes on every render (an inline filter object, `new Date()`, a function defined in the component) |
| Supabase usage spikes, "egress quota exceeded", or you burn through builder credits trying "Try to fix" | The looping fetch above, running on every user's browser |
| Typing in a form is laggy | A parent re-renders the whole page on each keystroke because the form state lives too high, or an effect re-fetches on each keystroke without debounce |

## Why it happens

React re-renders a component when its state or props change. `useEffect` runs after render whenever one of its dependencies changed. A loop appears when the effect's own work (setting state, creating a new object) makes a dependency look "changed" on the next render. Objects, arrays and functions are compared **by reference**, so `{}` is never equal to the previous `{}`.

AI builders produce this pattern constantly, because the generated code is locally sensible (fetch data when filters change) but the "filters" are an object literal recreated on each render.

## Diagnose (5 minutes)

1. Open the browser console on the broken page. The stack trace under `Maximum update depth exceeded` names the component and often the line of the offending `setState`.
2. If there is no error (silent loop): **React DevTools → Profiler → record** for two seconds. The component with hundreds of commits is the one looping.
3. **Network tab**, filter by `rest/v1`: a request repeating every few milliseconds with identical parameters is a fetch effect in a loop.
4. In the looping component, look at every `useEffect` and ask for each dependency: *is this a primitive (string, number, boolean) or a reference (object, array, function)?* References that are created inside the component are the suspects.

## Fix

### Case 1: the effect depends on the state it sets

```tsx
// BROKEN: filtered is set by the effect and is also a dependency
const [filtered, setFiltered] = useState<Item[]>([]);
useEffect(() => {
  setFiltered(items.filter(i => i.active));
}, [items, filtered]);
```

```tsx
// FIXED: derive it, no effect and no extra state at all
const filtered = useMemo(() => items.filter(i => i.active), [items]);
```

Rule: if a value can be computed from props/state, compute it during render (`useMemo` if it is expensive). Do not store it in state.

### Case 2: object / array / function dependency recreated every render

```tsx
// BROKEN: `filters` is a new object each render → effect runs each render → setState → render → …
const filters = { status: "active", owner: user.id };
useEffect(() => {
  fetchProjects(filters).then(setProjects);
}, [filters]);
```

```tsx
// FIXED (a): depend on the primitives inside it
useEffect(() => {
  fetchProjects({ status: "active", owner: user.id }).then(setProjects);
}, [user.id]);

// FIXED (b): stabilise the object
const filters = useMemo(() => ({ status: "active", owner: user.id }), [user.id]);
```

For functions passed down as props, wrap them in `useCallback` in the parent, or move them outside the component if they do not use props/state.

### Case 3: `setState` in the component body

```tsx
// BROKEN
function Page() {
  const [count, setCount] = useState(0);
  setCount(count + 1);          // runs on every render → "Too many re-renders"
  return <div>{count}</div>;
}
```

```tsx
// FIXED: state changes belong in handlers or effects
<button onClick={() => setCount(c => c + 1)}>+1</button>
```

The JSX variant looks like `onClick={setCount(count + 1)}` (called immediately) instead of `onClick={() => setCount(count + 1)}`.

### Case 4: fetch effect with async race

Even without a loop, a fetch effect that fires on every change can set stale data after the component unmounted or after the inputs changed again. Guard it:

```tsx
useEffect(() => {
  let cancelled = false;
  (async () => {
    const { data, error } = await supabase
      .from("projects")
      .select("*")
      .eq("owner", userId);
    if (!cancelled) {
      if (error) setError(error.message);
      else setProjects(data ?? []);
    }
  })();
  return () => { cancelled = true; };
}, [userId]);
```

### Case 5: use a data library instead of hand-rolled effects

Most Lovable/Bolt projects already include **TanStack Query** (`@tanstack/react-query`). Moving fetches into `useQuery` removes the whole class of problem: the query key is compared by value, requests are deduplicated, and refetching is controlled.

```tsx
import { useQuery } from "@tanstack/react-query";

const { data: projects = [], isLoading, error } = useQuery({
  queryKey: ["projects", userId, status],
  queryFn: async () => {
    const { data, error } = await supabase
      .from("projects").select("*").eq("owner", userId).eq("status", status);
    if (error) throw error;
    return data;
  },
  enabled: !!userId,
});
```

### Case 6: state updates that read state

```tsx
// fragile: depends on `count`, so the effect must list it, which can loop
useEffect(() => {
  const id = setInterval(() => setCount(count + 1), 1000);
  return () => clearInterval(id);
}, [count]);

// robust: functional update, no dependency on count
useEffect(() => {
  const id = setInterval(() => setCount(c => c + 1), 1000);
  return () => clearInterval(id);
}, []);
```

### Case 7: `onAuthStateChange` inside an effect that depends on the session

A classic in generated auth code: the effect subscribes to auth changes, the callback sets `session`, the effect depends on `session`, so it unsubscribes and resubscribes forever (and sometimes navigates on each cycle). Subscribe **once** with `[]` and read the current session inside the callback. See [Fix 2, section D](02-auth-redirects.md#d-fix-the-redirect-loop-with-a-loading-state) for a complete provider.

## How to prompt the builder so it does not come back

Paste this into Lovable/Bolt when asking for a fix:

> In `<Component>`, the `useEffect` on line N re-runs on every render because `<dep>` is a new object each time. Compute it with `useMemo` (or depend on its primitive fields), do not store derived data in state, and do not call setState in the component body. Do not suppress the eslint `react-hooks/exhaustive-deps` warning.

Prompts like "fix the infinite loop" usually make the builder add `// eslint-disable-next-line` and an empty dependency array, which hides the warning and introduces stale data instead.

## Verify

1. Console shows no `Maximum update depth` or `Too many re-renders` errors on the page, including after navigating away and back.
2. React DevTools Profiler: interacting with the page produces a handful of commits, not hundreds.
3. Network tab: each data request fires **once** per user action (or once per mount), not repeatedly.
4. Supabase → Reports → API: request counts drop back to what the user count justifies.
