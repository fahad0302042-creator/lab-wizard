---
Task ID: 1
Agent: main (super-z)
Task: Build the full Lab Wizard app — a mobile-first chemistry lab inventory app with a "Notebook" design system, mock data layer (Supabase to be added later), all 7 screens (Login, Dashboard, Chemicals, Apparatus, Scanner, Reports, Settings) + bottom nav.

Work Log:
- Initialized fullstack dev environment (Next.js 16 + TS + Tailwind 4 + shadcn/ui base)
- Installed qrcode.react + html5-qrcode for QR generation/scanning
- Built Notebook design system in globals.css: cream/paper palette, warm dark-mode variant, hatched stock-bar fills, washi-tape strips, torn-paper edges, ruled-line inputs, circled hand-written buttons, highlighter accent, print stylesheet
- Wired three Google Fonts via next/font: Caveat (display), Kalam (body/data), Architects Daughter (item-name accent)
- Built mock data layer (lib/store.ts): Zustand + localStorage persistence, clean seam for Supabase swap later — types in lib/types.ts match the spec's data model exactly
- Built core Notebook primitives (components/notebook/): NotebookCard with irregular corners + per-card tilt + washi tape + paperclip, HandDrawnBar with hatched fill, SectionTitle with squiggle underline, CircledButton, RuledInput/Textarea, MarginNote with hand-drawn arrow, FilterPill, Highlighter, ActivityEntry, Modal shell with torn-edge top
- Built hand-drawn SVG icon set (flask, beaker, clipboard, scan, chart, home, plus, minus, QR, pencil, trash, sun, moon, arrows, star, package, squiggle, margin-arrow, paperclip)
- Auth screen: notebook card centered with tilt, big flask doodle, ruled-line email/password inputs, circled "sign in" button, red-ink error annotations, sign-up toggle
- Dashboard: handwritten date + greeting, ruled-paper search, 4 KPI notebook cards (2x2 grid) with washi tape + hand-drawn icons, 7-day activity chart with hatched bars (amber=used / green=added), circled quick-action buttons, recent activity feed, low-stock margin-note callout
- Chemicals screen: "chemicals shelf" title with squiggle, ruled search, all/low/critical filter pills, notebook cards with Architects Daughter names + Kalam formulas + hand-drawn bars + handwritten captions, washi tape on ~1/3 (cycled), margin notes on flagged items, paperclip on critical, FAB add button
- Chemical modals: Add, Detail (with QR view link), Consume, Restock, Edit (with delete), QR view — all as notebook-card overlays with torn-edge top, handwritten field labels, circled confirm buttons, backdating date picker with red-ink warning, 5-second undo toasts wired to sonner
- Apparatus screen + modals: same structure but no QR, no condition; categories (glassware/balances/heating/measurement/other); breakage form styled in red ink with "−1 unit" in Caveat
- Scanner screen: html5-qrcode dynamic import, hand-drawn dashed viewfinder, recently-scanned chips (localStorage-backed), manual search fallback that opens detail on click
- Reports screen: 12-month selector tabs, chemicals/apparatus toggle, ruled-paper table (Name | Stock | −Used | =Left with color-coded =Left), generate-report (window.print) + clear-month actions, print stylesheet renders clean PDF
- Settings screen: hand-drawn day/night theme toggle (next-themes), user info + sign out, about section with live counts, danger-zone reset
- Bottom nav: 5 tabs (home/chems/scan/gear/reports) with hand-drawn line doodle icons, scan tab elevated as circled center button, sticky to bottom with safe-area inset
- Wired everything in app/page.tsx: auth gate, tab switching, all modals, settings overlay, floating ⚙ button

Verification (Agent Browser):
- Auth screen renders → sign in with demo creds → dashboard loads
- Add chemical (HCl, 500 mL) → appears in chemicals list with "100% full — plenty ✓"
- Open detail → consume 50 mL with note → quantity drops to 450, status updates to "90% full", undo toast appears, activity feed shows "used 50 mL Hydrochloric acid — Jul 3"
- Reports tab: table shows HCl with Stock 450mL / −Used 50 / =Left 450mL
- Scanner: manual search for "hydr" returns HCl, clicking opens detail modal, item appears in "recently scanned"
- Dark mode toggle works (warm low-light variant, not flat invert)
- Mobile viewport (390x844) renders correctly
- Lint clean (0 errors, 0 warnings)
- No console errors after fresh reload

Stage Summary:
- Full app delivered: 7 screens + bottom nav + 10 modals, all in Notebook design language
- Mock data layer isolated in lib/store.ts — Supabase swap is a drop-in replacement of method bodies, no consumer changes needed
- All spec rules respected: apparatus has no QR/condition, no seed data, Kalam for data-bearing text, Caveat reserved for display, hatched fills + restrained decoration (tape on ~1/3, margin notes only on <50% stock), dark mode is warm variant not flat invert, print output clean/functional
- Files: globals.css (design system), lib/{types,store,utils}.ts, components/notebook/{icons,primitives,modal}.tsx, components/{bottom-nav,theme-provider}.tsx, components/screens/{auth,dashboard,chemicals,apparatus,scanner,reports,settings}-screen.tsx, components/modals/{chemical,apparatus}-modals.tsx, app/{layout,page}.tsx
