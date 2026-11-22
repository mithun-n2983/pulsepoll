# PulsePoll Frontend

Clean, responsive, mobile-first React application powered by Vite, Tailwind CSS, Lucide React, and Supabase.

## Features
- **Student Quick Join (`/join` & `/`):** 6-digit code entry with auto-formatting (`XXX-XXX`), ultra-fast mobile loading, zero login/signup.
- **Projector / TV Present Mode (`/present/:pollId`):** High-contrast full-screen classroom presentation with massive QR code, bold 6-digit code, live ticking response counter, and auto-close countdown timer.
- **Professor Dashboard (`/dashboard`):** Real-time analytics, 1-click templates (Daily Class Feedback, Topic Clarity Check, Yes/No Quick Vote), one-click duplication, active/closed power toggling.
- **Poll / Quiz Builder (`/create`):** Multiple choice (MCQ), 1–5 Emoji sentiment ratings, and short answers with live character count.
- **Live Results & Analytics (`/results/:pollId`):** Aggregated visual charts and 1-click CSV export.

## Environment Variables
Create `.env` using `.env.example`:
```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_URL=http://localhost:5000/api
```

## Running Locally
```bash
npm install
npm run dev
```

## Production Build
```bash
npm run build
```
SPA rewrites are pre-configured in `vercel.json` for one-click Vercel deployment.
